# Maps a tracker to the subtype its issues are emitted as, per broker
# connection (#69). The subtype is the admin-chosen JSON-LD term that will be
# declared a subclass of the core Issue type in the instance's published
# context (design step 2); it travels as the `subtype` property because the
# target brokers reject multi-type entities (spike on #69).
class EmissionMapping < (defined?(ApplicationRecord) == 'constant' ? ApplicationRecord : ActiveRecord::Base)
  self.table_name = 'fiware_emission_mappings'

  # A JSON-LD term: ASCII letters and digits, starting with a letter.
  # CamelCase by convention (WorkOrder, RoadDamageReport), not enforced.
  SUBTYPE_PATTERN = /\A[A-Za-z][A-Za-z0-9]*\z/

  # The standard issue fields an admin may expose per mapping (#69, step 2b),
  # keyed by their published vocabulary term. Values name the Redmine field
  # label so the UI needs no locale keys of its own. assignee is listed last
  # and defaults off like everything else - publishing person names to a
  # shared broker is an explicit admin decision.
  STANDARD_FIELDS = {
    'description' => :field_description,
    'priority' => :field_priority,
    'category' => :field_category,
    'targetVersion' => :field_fixed_version,
    'startDate' => :field_start_date,
    'dueDate' => :field_due_date,
    'estimatedTime' => :field_estimated_hours,
    'percentDone' => :field_done_ratio,
    'parent' => :field_parent_issue,
    'assignee' => :field_assigned_to
  }.freeze

  # Terms a subtype must not shadow in the published context (#69, step 2):
  # the core vocabulary, the exposable standard terms, the context's prefixes,
  # and the NGSI-LD/core-context terms every entity relies on. Compared
  # case-insensitively.
  RESERVED_SUBTYPES = (
    RedmineGttFiware::InstanceContext::CORE_TERMS +
    STANDARD_FIELDS.keys +
    %w[rdfs gttfiware inst id type location dateCreated dateModified dateObserved]
  ).map(&:downcase).freeze

  # Tolerant JSON coder: a hand-edited or corrupted column value degrades to
  # "nothing exposed" instead of raising - the public context endpoint and
  # every issue save iterate mappings, so a broken row must never take them
  # down.
  class ExposedAttributesCoder
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

  serialize :exposed_attributes, coder: ExposedAttributesCoder

  belongs_to :broker_connection
  belongs_to :tracker

  validates :subtype, presence: true,
                      format: { with: SUBTYPE_PATTERN, message: I18n.t('model.emission_mapping.invalid_subtype') }
  validate :subtype_must_not_shadow_reserved_terms
  validates :tracker_id, uniqueness: { scope: :broker_connection_id }
  # Emission is NGSI-LD only in v1 (the entity payload is JSON-LD).
  validate :connection_must_be_ngsi_ld

  # The exposed standard fields, always a cleaned subset of the catalog -
  # unknown keys (a stale UI, a hand-edited row) are dropped on read and
  # write, so IssueEntity can trust every entry.
  def exposed_standard_fields
    Array((exposed_attributes || {})['standard']) & STANDARD_FIELDS.keys
  end

  def exposed_standard_fields=(fields)
    self.exposed_attributes = (exposed_attributes || {}).merge(
      'standard' => Array(fields).map(&:to_s) & STANDARD_FIELDS.keys
    )
  end

  # Default subtype suggestion for a tracker: its name as a JSON-LD term when
  # that yields something usable, the generic suggestion otherwise (tracker
  # names are free text, often non-ASCII).
  def self.suggested_subtype(tracker)
    term = tracker.name.to_s.gsub(/[^A-Za-z0-9]+/, ' ').split.map(&:capitalize).join
    term.match?(SUBTYPE_PATTERN) ? term : 'WorkOrder'
  end

  private

  def connection_must_be_ngsi_ld
    return if broker_connection.nil? || broker_connection.ngsi_ld?

    errors.add :broker_connection, I18n.t('model.emission_mapping.connection_not_ngsi_ld')
  end

  def subtype_must_not_shadow_reserved_terms
    return unless RESERVED_SUBTYPES.include?(subtype.to_s.downcase)

    errors.add :subtype, I18n.t('model.emission_mapping.reserved_subtype')
  end
end
