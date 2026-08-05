require 'net/http'

module RedmineGttFiware
  # Queries a broker for other organizations' Issue entities referring to the
  # same source entity (#70): the shared-refersTo definition of "the same
  # problem". Used at notification time (4a) and by the issue-page panel (4b).
  #
  # Queries expand type/attribute names through the published core vocabulary
  # (one stable public context, so any instance's query matches any properly
  # configured instance's entities). Failures degrade to an empty list -
  # federation awareness must never break notification processing or an
  # issue page.
  class FederationSiblings
    # The published core vocabulary, usable as a JSON-LD @context.
    CONTEXT_URL = 'https://gtt-project.org/ns/fiware.jsonld'.freeze
    LINK_HEADER = %(<#{CONTEXT_URL}>; rel="http://www.w3.org/ns/json-ld#context"; type="application/ld+json").freeze
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

    # Characters legal in the URNs this plugin queries by. The entity id
    # comes from an untrusted notification payload and is interpolated into
    # the quoted NGSI-LD q literal below, so anything that could break out of
    # the quotes (") or alter the query grammar (;|()<>= ...) is rejected
    # here rather than escaped: no real URN contains such characters.
    QUERYABLE_URN_PATTERN = /\A[A-Za-z0-9:._~-]+\z/

    # Foreign Issue entities whose refersTo points at entity_urn, own
    # instance excluded (that is what makes them *siblings*).
    def for_entity(entity_urn)
      return [] unless entity_urn.to_s.match?(QUERYABLE_URN_PATTERN)

      # fetch returns nil on failure, and skip_nil keeps that out of the
      # cache: one broker hiccup must not blank the issue-page panel for the
      # whole TTL. A genuinely empty sibling list ([]) is cached as usual.
      Rails.cache.fetch(cache_key(entity_urn), expires_in: CACHE_TTL, skip_nil: true) do
        fetch(entity_urn)
      end || []
    end

    private

    def cache_key(entity_urn)
      ['gtt_fiware_siblings', @connection.id, entity_urn]
    end

    # Returns the siblings, or nil on failure (the caller treats nil as "no
    # siblings" but keeps it out of the cache).
    def fetch(entity_urn)
      query = Rack::Utils.build_query(type: 'Issue', limit: QUERY_LIMIT,
                                      q: %(refersTo=="#{entity_urn}"))
      response = BrokerHttp.request(:get, "#{@connection.api_base}/entities?#{query}",
                                    connection: @connection, token: @connection.auth_token,
                                    headers: { 'Accept' => 'application/ld+json', 'Link' => LINK_HEADER })
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn "[FIWARE] Sibling query on #{@connection.name} answered #{response.code}"
        return nil
      end

      parse(response.body)
    rescue StandardError => e
      Rails.logger.warn "[FIWARE] Sibling query on #{@connection.name} failed: #{e.class}: #{e.message}"
      nil
    end

    def parse(body)
      entities = JSON.parse(body)
      return [] unless entities.is_a?(Array)

      entities.filter_map { |entity| sibling(entity) }
    rescue JSON::ParserError
      []
    end

    # Foreign = the URN's instance id differs from ours. Entities without our
    # URN shape (hand-made Issue entities from non-Redmine producers) count
    # as foreign too: someone else works on it, whoever they are.
    def sibling(entity)
      urn = entity['id'].to_s
      org = IssueUrn.instance_of(urn)
      return nil if org.present? && org == Emitter.instance_id

      Sibling.new(
        urn: urn,
        org: org || 'external',
        subtype: value_of(entity['subtype']),
        status: value_of(entity['status']),
        status_label: value_of(entity['statusLabel']),
        title: value_of(entity['title']),
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
