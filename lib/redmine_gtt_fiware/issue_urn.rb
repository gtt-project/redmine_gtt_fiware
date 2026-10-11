module RedmineGttFiware
  # The URN shape of emitted entities:
  #
  #   urn:ngsi-ld:Issue:redmine:<instance identifier>:<issue id>
  #
  # The `Issue` segment dates from the retired GTT Issue vocabulary. Task
  # entities (#152) keep it on purpose: ids must never change, or every
  # entity already on a broker would be re-identified.
  #
  # This is wire protocol shared between federating instances, so building
  # and parsing live here in one place: a format change that misses a call
  # site silently breaks the emission echo guard or the organization
  # attribution in federation notes.
  module IssueUrn
    PREFIX = 'urn:ngsi-ld:Issue:redmine'.freeze
    INSTANCE_PATTERN = /\Aurn:ngsi-ld:Issue:redmine:([^:]+):/

    module_function

    # The URN for an issue emitted by this instance.
    def build(issue)
      "#{PREFIX}:#{Emitter.instance_id}:#{issue.id}"
    end

    # The instance identifier inside a URN, or nil when the URN does not
    # have this shape (hand-made entities from non-Redmine producers).
    def instance_of(urn)
      urn.to_s[INSTANCE_PATTERN, 1]
    end

    # Whether the URN names an entity this instance emitted itself.
    def own?(urn)
      instance = Emitter.instance_id
      instance.present? && instance_of(urn) == instance
    end
  end
end
