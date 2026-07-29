require 'securerandom'
require 'active_support/security_utils'

class SubscriptionTemplate < (defined?(ApplicationRecord) == 'constant' ? ApplicationRecord : ActiveRecord::Base)
  self.table_name = "fiware_subscription_templates"

  # Number of random bytes for the per-template webhook secret. The broker
  # stores this secret and sends it back on every notification; the
  # notification endpoint authenticates on it alone (no Redmine API key is
  # ever embedded in a broker payload). See #58.
  WEBHOOK_SECRET_BYTES = 32

  after_initialize :set_default_alteration_types, if: :new_record?
  after_initialize :set_default_notify_on_metadata_change, if: :new_record?
  before_create :ensure_webhook_secret

  belongs_to :project, optional: false
  # Broker configuration (URL, standard, tenant headers, auth) lives on the
  # connection since #67; the template holds the subscription itself.
  belongs_to :broker_connection, optional: false
  belongs_to :tracker, optional: false
  belongs_to :issue_status, optional: false
  belongs_to :member, optional: false
  belongs_to :version, optional: true
  belongs_to :issue_category, optional: true
  belongs_to :issue_priority, optional: true, class_name: 'IssuePriority', foreign_key: 'issue_priority_id'

  delegate :standard, :fiware_service, :fiware_servicepath, :ngsi_ld?, :stored_auth?,
           to: :broker_connection, allow_nil: true

  # Per-tracker custom field templates (#103, phase 2): a JSON object mapping
  # issue custom field ids (string keys) to template strings. Tolerant on
  # read like EmissionMapping's coder: malformed stored JSON reads as {}.
  class CustomFieldValuesCoder
    def self.dump(value)
      JSON.dump(value || {})
    end

    def self.load(value)
      return {} if value.blank?

      parsed = JSON.parse(value)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end
  end

  serialize :issue_custom_field_values, coder: CustomFieldValuesCoder

  # Normalizes form input (ActionController::Parameters or a hash with mixed
  # key types) into plain string keys and values, dropping blank templates so
  # untouched inputs never store empty strings.
  def issue_custom_field_values=(value)
    hash = value.respond_to?(:to_h) && value ? value.to_h : {}
    cleaned = hash.each_with_object({}) do |(key, template), result|
      result[key.to_s] = template.to_s unless template.to_s.strip.empty?
    end
    super(cleaned)
  end

  STATUS = ['active', 'inactive', 'oneshot'].freeze

  # Federation awareness at creation time (#70, 4a): what to do when another
  # organization's Issue entity already refers to the notifying entity.
  FEDERATION_POLICIES = ['off', 'annotate', 'suppress'].freeze
  GEOMETRIES = ['point', 'line', 'polygon', 'box'].freeze
  ALTERATION_TYPES = ['entityCreate', 'entityChange', 'entityUpdate', 'entityDelete'].freeze

  # Maps the stored NGSIv2 alteration types to their NGSI-LD notification
  # triggers. NGSI-LD replaces `alterationTypes` with `notificationTrigger`
  # and has no distinct "change" trigger, so both entityChange and
  # entityUpdate collapse to entityUpdated (deduplicated in #notification_triggers).
  NGSI_LD_TRIGGER_MAP = {
    'entityCreate' => 'entityCreated',
    'entityChange' => 'entityUpdated',
    'entityUpdate' => 'entityUpdated',
    'entityDelete' => 'entityDeleted'
  }.freeze

  validates :status, inclusion: { in: STATUS, message: I18n.t('model.subscription_template.valid_status') }
  validates :federation_policy, inclusion: { in: FEDERATION_POLICIES }
  validates :throttling, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :expression_geometry, inclusion: { in: GEOMETRIES, message: I18n.t('model.subscription_template.valid_geometry') }, allow_blank: true
  # allow_nil: a template saved with no alteration types stores nil (see
  # serialize_alteration_types), which is valid persisted state - the
  # builders simply omit the field. Without allow_nil every later validated
  # update on such a template fails (new records are shielded only by the
  # after_initialize default).
  validates :alteration_types, inclusion: { in: ALTERATION_TYPES, message: I18n.t('model.subscription_template.valid_alteration_types') }, allow_nil: true

  validates :name, presence: true
  validates :subject, presence: true
  validates :description, presence: true
  validates :entities_string, presence: true
  # NGSI-LD resolves the entity/attribute terms through @context, so an LD
  # template must have one: its own or the connection's default.
  validates :effective_context, presence: true, if: :ngsi_ld?

  validate :name_uniqueness
  validate :take_json_entities
  validate :take_json_geometry
  validate :take_json_attachments
  validate :attrs_must_be_array_of_strings
  validate :geo_query_fields_must_be_all_or_none

  # A tracker that disables a core field must not keep a stored value for it
  # (#103): the form hides the selects, but hidden inputs still submit, and
  # the form is not the only writer.
  before_validation :clear_tracker_disabled_fields
  before_save :serialize_alteration_types
  after_find :deserialize_alteration_types

  def self.generate_webhook_secret
    SecureRandom.hex(WEBHOOK_SECRET_BYTES)
  end

  def broker_url
    broker_connection&.url
  end

  # The @context for this template's NGSI-LD subscription: the template's own
  # value overrides the connection's default.
  # A federation watch (#70, 4c) subscribes to the emitted Issue type, so it
  # must expand Issue/refersTo/status through the published core vocabulary -
  # the same context every emitting instance anchors its terms in. Otherwise
  # the template/connection context wins as usual.
  def effective_context
    return RedmineGttFiware::FederationSiblings::CONTEXT_URL if federation_watch?

    context.presence || broker_connection&.context
  end

  # Minimum interval between notifications for this subscription (#95). Same
  # precedence as the context: template overrides the connection default.
  # 0 is a meaningful value (no throttling), so test for nil, not presence.
  def effective_throttling
    return throttling unless throttling.nil?
    return broker_connection.throttling unless broker_connection&.throttling.nil?

    BrokerConnection::DEFAULT_THROTTLING
  end

  # The NGSI-LD notification triggers for this template's alteration types,
  # deduplicated (see NGSI_LD_TRIGGER_MAP). Empty for a template with no
  # alteration types configured.
  def notification_triggers
    Array(alteration_types).filter_map { |type| NGSI_LD_TRIGGER_MAP[type] }.uniq
  end

  # Persist a secret only if the template does not already have one (e.g. a
  # template created before the webhook_secret column existed). The secret is
  # otherwise stable for the life of the template: it must not change while a
  # subscription is live on the broker, or the broker would keep sending a
  # secret the plugin no longer accepts. Backfilling a blank secret is safe
  # because nothing on the broker relies on the previous (absent) value.
  def ensure_webhook_secret!
    return if webhook_secret.present?

    update_column(:webhook_secret, self.class.generate_webhook_secret)
  end

  # Constant-time comparison of a provided secret against the stored one.
  # Returns false (never raises) for a blank stored or provided secret.
  def valid_webhook_secret?(provided)
    provided = provided.to_s
    secret = webhook_secret.to_s
    return false if secret.empty? || provided.empty?

    ActiveSupport::SecurityUtils.secure_compare(secret, provided)
  end

  attr_accessor :threshold_create_hours
  # Override the getter for threshold_create_hours
  def threshold_create_hours
    threshold_create / 3600 if threshold_create
  end

  # Override the setter for threshold_create_hours
  def threshold_create_hours=(hours)
    self.threshold_create = hours.to_i * 3600
  end

  attr_writer :entities_string
  def entities_string
    @entities_string ||= entities.present? ? JSON.pretty_generate(entities) : ''
  end

  attr_writer :geometry_string
  def geometry_string
    @geometry_string ||= geometry.present? ? JSON.pretty_generate(geometry) : ''
  end

  attr_writer :attachments_string
  def attachments_string
    @attachments_string ||= attachments.present? ? JSON.pretty_generate(attachments) : ''
  end

  private

  def set_default_alteration_types
    self.alteration_types ||= ["entityCreate", "entityChange"]
  end

  def set_default_notify_on_metadata_change
    self.notify_on_metadata_change = true if notify_on_metadata_change.nil?
  end

  # Parsable JSON is not enough: the subscription builders and the form's
  # structured picker both expect an array of entity objects, so '{}' or
  # '[1]' must fail validation here instead of breaking publish later.
  # Blank input is left to the presence validation (one error, and no
  # TypeError from JSON.parse(nil)); to_s keeps a stray non-string writer
  # value on the graceful rescue path instead of raising.
  def take_json_entities
    return if entities_string.blank?

    parsed = JSON.parse(entities_string.to_s)
    unless parsed.is_a?(Array) && parsed.any? && parsed.all? { |e| e.is_a?(Hash) }
      errors.add :entities_string, I18n.t('model.subscription_template.must_be_valid_array_of_objects')
      return
    end
    self.entities = parsed
  rescue JSON::ParserError
    errors.add :entities_string, I18n.t(:error_invalid_json)
  end

  def take_json_geometry
    return if geometry_string.blank?

    self.geometry = JSON.parse(geometry_string)
  rescue JSON::ParserError
    errors.add :geometry_string, I18n.t(:error_invalid_json)
  end

  # 'null' (from the picker with no rows) clears the stored attachments; any
  # other value must be an array of attachment objects -- a parsable but
  # wrong-shaped value ('{}', '[1]') previously slipped through validation
  # and broke the picker and the download step downstream.
  def take_json_attachments
    return if attachments_string.blank?

    parsed = JSON.parse(attachments_string.to_s)
    if parsed.nil?
      self.attachments = nil
      return
    end
    unless parsed.is_a?(Array) && parsed.all? { |a| a.is_a?(Hash) }
      errors.add :attachments_string, I18n.t('model.subscription_template.must_be_valid_array_of_objects')
      return
    end
    self.attachments = parsed
  rescue JSON::ParserError
    errors.add :attachments_string, I18n.t('model.subscription_template.must_be_valid_array_of_objects')
  end

  def clear_tracker_disabled_fields
    return unless tracker
    disabled = tracker.disabled_core_fields
    self.issue_priority_id = nil if disabled.include?('priority_id')
    self.issue_category_id = nil if disabled.include?('category_id')
    self.version_id = nil if disabled.include?('fixed_version_id')
    # Same rule for custom fields: values for fields the tracker does not
    # carry must not persist (the form disables their inputs, but the form is
    # not the only writer).
    if issue_custom_field_values.present?
      allowed = tracker.custom_field_ids.map(&:to_s)
      self.issue_custom_field_values = issue_custom_field_values.slice(*allowed)
    end
  end

  def serialize_alteration_types
    self.alteration_types = alteration_types.empty? ? nil : alteration_types.to_json if alteration_types.is_a?(Array)
  end

  def deserialize_alteration_types
    self.alteration_types = JSON.parse(alteration_types) if alteration_types.is_a?(String)
  end

  def attrs_must_be_array_of_strings
    return if attrs.blank?

    attrs_array = JSON.parse(attrs) rescue nil
    unless attrs_array.is_a?(Array) && attrs_array.all? { |element| element.is_a?(String) }
      errors.add :attrs, I18n.t('model.subscription_template.attrs_must_be_array_of_strings')
    end
  end

  def geo_query_fields_must_be_all_or_none
    geo_query_fields = [expression_georel, expression_geometry, expression_coords]
    if geo_query_fields.any?(&:present?) && geo_query_fields.any?(&:blank?)
      errors.add :base, I18n.t('model.subscription_template.geo_query_fields_must_be_all_or_none')
    end
  end

  def name_uniqueness
    scope = SubscriptionTemplate.where.not(id: id).where(name: name, project_id: project_id)

    if scope.any?
      errors.add :name, I18n.t('model.subscription_template.name_uniqueness')
    end
  end

  def ensure_webhook_secret
    self.webhook_secret = self.class.generate_webhook_secret if webhook_secret.blank?
  end
end
