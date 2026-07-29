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
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10
    CACHE_TTL = 60 # seconds; the issue-page panel refetches at most this often

    Sibling = Struct.new(:urn, :org, :subtype, :status, :status_label, :title, :source, keyword_init: true) do
      def open?
        status == 'open'
      end
    end

    def initialize(connection)
      @connection = connection
    end

    # Foreign Issue entities whose refersTo points at entity_urn, own
    # instance excluded (that is what makes them *siblings*).
    def for_entity(entity_urn)
      return [] if entity_urn.blank?

      Rails.cache.fetch(cache_key(entity_urn), expires_in: CACHE_TTL) do
        fetch(entity_urn)
      end
    end

    private

    def cache_key(entity_urn)
      ['gtt_fiware_siblings', @connection.id, entity_urn]
    end

    def fetch(entity_urn)
      uri = URI(@connection.url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      query = Rack::Utils.build_query(type: 'Issue', q: %(refersTo=="#{entity_urn}"))
      request = Net::HTTP::Get.new("#{ld_path(uri)}/entities?#{query}", headers)
      response = http.request(request)
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn "[FIWARE] Sibling query on #{@connection.name} answered #{response.code}"
        return []
      end

      parse(response.body)
    rescue StandardError => e
      Rails.logger.warn "[FIWARE] Sibling query on #{@connection.name} failed: #{e.class}: #{e.message}"
      []
    end

    # Preserve an explicit /ngsi-ld/v1 path in the connection URL, append the
    # default prefix otherwise (same convention as Emitter and
    # SubscriptionRequest).
    def ld_path(uri)
      path = uri.path.chomp('/')
      path.match?(%r{/ngsi-ld/v1\z}) ? path : "#{path}/ngsi-ld/v1"
    end

    def headers
      result = { 'Accept' => 'application/ld+json', 'Link' => LINK_HEADER }
      result['NGSILD-Tenant'] = @connection.fiware_service if @connection.fiware_service.present?
      pair = @connection.token_header_pair(@connection.auth_token)
      result[pair.first] = pair.last if pair
      result
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
      org = urn[%r{\Aurn:ngsi-ld:Issue:redmine:([^:]+):}, 1]
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
