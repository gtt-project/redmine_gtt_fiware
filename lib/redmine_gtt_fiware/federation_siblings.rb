require 'net/http'

module RedmineGttFiware
  # Queries a broker for other organizations' Issue entities referring to the
  # same source entity (#70): the shared-refersTo definition of "the same
  # problem". Used at notification time (4a) and by the issue-page panel (4b).
  #
  # Queries expand type/attribute names through a published vocabulary (one
  # stable public context, so any instance's query matches any properly
  # configured instance's entities). Instances emit either GTT Issue
  # entities or datamodels.jp Task entities (#152), and the two vocabularies
  # give refersTo different IRIs, so one query per vocabulary is sent and the
  # results are merged. Failures degrade to an empty list - federation
  # awareness must never break notification processing or an issue page.
  class FederationSiblings
    # The published core vocabulary, usable as a JSON-LD @context.
    CONTEXT_URL = 'https://gtt-project.org/ns/fiware.jsonld'.freeze
    LINK_HEADER = %(<#{CONTEXT_URL}>; rel="http://www.w3.org/ns/json-ld#context"; type="application/ld+json").freeze
    TASK_LINK_HEADER = %(<#{EmissionVocabulary::TASK_CONTEXT}>; rel="http://www.w3.org/ns/json-ld#context"; type="application/ld+json").freeze

    # The entity type queried in each vocabulary and its Link header.
    VOCABULARIES = {
      'Issue' => LINK_HEADER,
      'Task' => TASK_LINK_HEADER
    }.freeze

    # RFC 8984 progress values that mean the work is over; a Task with any
    # other progress is open, like an Issue with status open.
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

    # Foreign Issue and Task entities whose refersTo points at entity_urn,
    # own instance excluded (that is what makes them *siblings*).
    def for_entity(entity_urn)
      return [] unless entity_urn.to_s.match?(QUERYABLE_URN_PATTERN)

      # Only complete answers are cached: one broker hiccup must not blank
      # (or halve) the issue-page panel for the whole TTL. A genuinely empty
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

    # Returns [siblings, complete]. A failed query contributes nothing and
    # marks the answer incomplete; the other vocabulary's siblings are still
    # returned (a broker that cannot load one context must not hide the
    # work orders of the other).
    def fetch(entity_urn)
      results = VOCABULARIES.map { |type, link| fetch_type(entity_urn, type, link) }
      [results.compact.flatten.uniq(&:urn), results.none?(&:nil?)]
    end

    def fetch_type(entity_urn, type, link)
      query = Rack::Utils.build_query(type: type, limit: QUERY_LIMIT,
                                      q: %(refersTo=="#{entity_urn}"))
      response = BrokerHttp.request(:get, "#{@connection.api_base}/entities?#{query}",
                                    connection: @connection, token: @connection.auth_token,
                                    headers: { 'Accept' => 'application/ld+json', 'Link' => link })
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn "[FIWARE] Sibling query (#{type}) on #{@connection.name} answered #{response.code}"
        return nil
      end

      parse(response.body, type)
    rescue StandardError => e
      Rails.logger.warn "[FIWARE] Sibling query (#{type}) on #{@connection.name} failed: #{e.class}: #{e.message}"
      nil
    end

    # The broker answered the query for one type, compacted with that
    # vocabulary's context, so each answer is read with its attribute names.
    def parse(body, type)
      entities = JSON.parse(body)
      return [] unless entities.is_a?(Array)

      entities.filter_map { |entity| type == 'Task' ? task_sibling(entity) : sibling(entity) }
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

    # A Task entity (#152) read into the same Sibling: name is the title and
    # progress is normalized to open/closed, so the federation policy and
    # the notes treat both vocabularies alike.
    def task_sibling(entity)
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
