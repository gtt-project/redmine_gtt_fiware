require 'net/http'

module RedmineGttFiware
  # Queries a broker for other organizations' Task entities (#152)
  # referring to the same source entity (#70): the shared-refersTo
  # definition of "the same problem". Used at notification time (4a) and by
  # the issue-page panel (4b).
  #
  # Queries expand type/attribute names through the published datamodels.jp
  # task vocabulary (one stable public context, so any instance's query
  # matches any properly configured instance's entities). type=Task matches
  # GTT entities emitted as `Issue` too: brokers store the expanded type,
  # and both names expand to the same IRI. Failures degrade to an
  # empty list - federation awareness must never break notification
  # processing or an issue page.
  class FederationSiblings
    TASK_LINK_HEADER = %(<#{EmissionVocabulary::TASK_CONTEXT}>; rel="http://www.w3.org/ns/json-ld#context"; type="application/ld+json").freeze

    # RFC 8984 progress values that mean the work is over; a Task with any
    # other progress is open.
    FINISHED_PROGRESS = %w[completed failed cancelled].freeze

    CACHE_TTL = 60 # seconds; the issue-page panel refetches at most this often

    # Explicit page size: brokers default to small pages (Orion-LD: 20) and
    # would silently truncate the sibling list without it.
    QUERY_LIMIT = 100

    Sibling = Struct.new(:urn, :org, :subtype, :status, :status_label, :title, :source, keyword_init: true) do
      def open?
        status == 'open'
      end
    end

    def initialize(connection)
      @connection = connection
    end

    # open or closed for an RFC 8984 progress value; nil when there is none
    # (the vocabulary allows leaving it out when no value fits).
    def self.status_from_progress(progress)
      return nil if progress.blank?

      FINISHED_PROGRESS.include?(progress.to_s) ? 'closed' : 'open'
    end

    # Characters legal in the URNs this plugin queries by. The entity id
    # comes from an untrusted notification payload and is interpolated into
    # the quoted NGSI-LD q literal below, so anything that could break out of
    # the quotes (") or alter the query grammar (;|()<>= ...) is rejected
    # here rather than escaped: no real URN contains such characters.
    QUERYABLE_URN_PATTERN = /\A[A-Za-z0-9:._~-]+\z/

    # Foreign Task entities whose refersTo points at entity_urn,
    # own instance excluded (that is what makes them *siblings*).
    def for_entity(entity_urn)
      return [] unless entity_urn.to_s.match?(QUERYABLE_URN_PATTERN)

      # Only complete answers are cached: one broker hiccup must not blank the
      # issue-page panel for the whole TTL. A genuinely empty
      # sibling list ([]) is cached as usual.
      key = cache_key(entity_urn)
      cached = Rails.cache.read(key)
      return cached if cached

      siblings, complete = fetch(entity_urn)
      Rails.cache.write(key, siblings, expires_in: CACHE_TTL) if complete
      siblings
    end

    private

    def cache_key(entity_urn)
      ['gtt_fiware_siblings', @connection.id, entity_urn]
    end

    # Returns [siblings, complete]. A failed query yields no siblings and
    # marks the answer incomplete.
    def fetch(entity_urn)
      query = Rack::Utils.build_query(type: 'Task', limit: QUERY_LIMIT,
                                      q: %(refersTo=="#{entity_urn}"))
      response = BrokerHttp.request(:get, "#{@connection.api_base}/entities?#{query}",
                                    connection: @connection, token: @connection.auth_token,
                                    headers: { 'Accept' => 'application/ld+json', 'Link' => TASK_LINK_HEADER })
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn "[FIWARE] Sibling query on #{@connection.name} answered #{response.code}"
        return [[], false]
      end

      [parse(response.body), true]
    rescue StandardError => e
      Rails.logger.warn "[FIWARE] Sibling query on #{@connection.name} failed: #{e.class}: #{e.message}"
      [[], false]
    end

    # The broker answered compacted with the task context, so each entity
    # is read with the task attribute names.
    def parse(body)
      entities = JSON.parse(body)
      return [] unless entities.is_a?(Array)

      entities.filter_map { |entity| sibling(entity) }
    rescue JSON::ParserError
      []
    end

    # A Task entity read into a Sibling: name is the title and progress is
    # normalized to open/closed for the federation policy and the notes.
    # Foreign = the URN's instance id differs from ours. Entities without our
    # URN shape (hand-made Task entities from non-Redmine producers) count
    # as foreign too: someone else works on it, whoever they are.
    def sibling(entity)
      urn = entity['id'].to_s
      org = IssueUrn.instance_of(urn)
      return nil if org.present? && org == Emitter.instance_id

      Sibling.new(
        urn: urn,
        org: org || 'external',
        subtype: value_of(entity['subtype']),
        status: self.class.status_from_progress(value_of(entity['progress'])),
        status_label: value_of(entity['statusLabel']),
        title: value_of(entity['name']),
        source: safe_url(value_of(entity['source']))
      )
    end

    # Broker data is untrusted: source is rendered as a link (panel) and
    # embedded in journal notes, so anything but a plain http(s) URL is
    # dropped at this boundary (a javascript: URL would be XSS).
    def safe_url(value)
      uri = URI.parse(value.to_s)
      uri.is_a?(URI::HTTP) && uri.host.present? ? value.to_s : nil
    rescue URI::InvalidURIError
      nil
    end

    # Notification-style ({"value" => ...}) and keyValues-style (plain)
    # attribute shapes both occur in the wild.
    def value_of(attribute)
      attribute.is_a?(Hash) ? attribute['value'] : attribute
    end
  end
end
