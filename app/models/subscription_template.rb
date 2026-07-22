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
  belongs_to :tracker, optional: false
  belongs_to :issue_status, optional: false
  belongs_to :member, optional: false
  belongs_to :version, optional: true
  belongs_to :issue_category, optional: true
  belongs_to :issue_priority, optional: true, class_name: 'IssuePriority', foreign_key: 'issue_priority_id'

  STANDARDS = ['NGSIv2'].freeze
  STATUS = ['active', 'inactive', 'oneshot'].freeze
  GEOMETRIES = ['point', 'line', 'polygon', 'box'].freeze
  ALTERATION_TYPES = ['entityCreate', 'entityChange', 'entityUpdate', 'entityDelete'].freeze

  validates :standard, inclusion: { in: STANDARDS, message: I18n.t('model.subscription_template.valid_standard') }
  validates :status, inclusion: { in: STATUS, message: I18n.t('model.subscription_template.valid_status') }
  validates :expression_geometry, inclusion: { in: GEOMETRIES, message: I18n.t('model.subscription_template.valid_geometry') }, allow_blank: true
  validates :alteration_types, inclusion: { in: ALTERATION_TYPES, message: I18n.t('model.subscription_template.valid_alteration_types') }

  validates :name, presence: true
  validates :broker_url, presence: true
  validates :subject, presence: true
  validates :description, presence: true
  validates :entities_string, presence: true

  validate :name_uniqueness
  validate :take_json_entities
  validate :take_json_geometry
  validate :take_json_attachments
  validate :attrs_must_be_array_of_strings
  validate :geo_query_fields_must_be_all_or_none

  before_save :serialize_alteration_types
  after_find :deserialize_alteration_types

  def self.generate_webhook_secret
    SecureRandom.hex(WEBHOOK_SECRET_BYTES)
  end

  # Assign a fresh secret and persist it. Called on each (re)publish so the
  # credential the broker holds is rotated every time the subscription is sent.
  def rotate_webhook_secret!
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

  def take_json_entities
    self.entities = JSON.parse(entities_string)
  rescue JSON::ParserError
    errors.add :entities_string, I18n.t(:error_invalid_json)
  end

  def take_json_geometry
    return if geometry_string.blank?

    self.geometry = JSON.parse(geometry_string)
  rescue JSON::ParserError
    errors.add :geometry_string, I18n.t(:error_invalid_json)
  end

  def take_json_attachments
    return if attachments_string.blank?

    self.attachments = JSON.parse(attachments_string)
  rescue JSON::ParserError
    errors.add :attachments_string, I18n.t('model.subscription_template.must_be_valid_array_of_objects')
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
