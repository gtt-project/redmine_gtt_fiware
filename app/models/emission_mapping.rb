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

  # Terms a subtype must not shadow in the published context (#69, step 2):
  # the core vocabulary, the context's prefixes, and the NGSI-LD/core-context
  # terms every entity relies on. Compared case-insensitively.
  RESERVED_SUBTYPES = (
    RedmineGttFiware::InstanceContext::CORE_TERMS +
    %w[rdfs gttfiware inst id type location dateCreated dateModified dateObserved]
  ).map(&:downcase).freeze

  belongs_to :broker_connection
  belongs_to :tracker

  validates :subtype, presence: true,
                      format: { with: SUBTYPE_PATTERN, message: I18n.t('model.emission_mapping.invalid_subtype') }
  validate :subtype_must_not_shadow_reserved_terms
  validates :tracker_id, uniqueness: { scope: :broker_connection_id }
  # Emission is NGSI-LD only in v1 (the entity payload is JSON-LD).
  validate :connection_must_be_ngsi_ld

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
