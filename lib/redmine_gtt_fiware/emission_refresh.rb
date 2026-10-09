require 'erb'
require 'net/http'

module RedmineGttFiware
  # Brings an already-existing broker entity in line with the current local
  # representation (#146). The Emitter lands here when its create attempt
  # answered 409.
  #
  # Two divergences need more than a plain attribute update:
  #
  # - Attributes that appeared locally after the first emission (a field
  #   newly exposed in the mapping, a geometry added to the issue). The
  #   update goes through POST /entities/{id}/attrs (append, which also
  #   overwrites existing attributes) rather than PATCH, because brokers on
  #   spec revisions <= 1.5 ignore attributes they do not know on the PATCH
  #   and would silently drop the new ones.
  #
  # - Attributes the broker still has but the current representation no
  #   longer carries (assignee cleared, exposure switched off, geometry
  #   removed). Each is removed with DELETE /entities/{id}/attrs/{name}
  #   (ETSI GS CIM 009 clause 5.6.5) - deliberately NOT with the
  #   urn:ngsi-ld:null value of clause 4.5.0: brokers that do not implement
  #   the null convention (GeonicDB, verified 2026-08-05) store the null URN
  #   as a literal attribute value, which is worse than the stale value it
  #   was meant to remove. The attribute DELETE has been in the spec since
  #   the earliest revisions and is unambiguous everywhere.
  #
  # The stale set comes from reading the broker's entity back (fetch and
  # diff), not from a local memory of past emissions: it needs no schema,
  # and it self-heals when the broker was changed by someone else. When the
  # read fails the deletion pass is skipped for this run; the next update
  # gets another chance.
  #
  # One divergence attributes cannot fix: the entity type. An append never
  # changes it, so after the admin switched the emission vocabulary (#152,
  # Issue <-> Task, same id) the broker entity is deleted and created anew
  # from the current representation.
  class EmissionRefresh
    # Not attributes: identity, context, and the broker-managed timestamps
    # (CIM 009 system attributes, which a normalized entity may embed).
    NON_ATTRIBUTE_KEYS = %w[id type @context createdAt modifiedAt].freeze

    def initialize(connection, entity)
      @connection = connection
      @entity = entity
    end

    # Returns the response the Emitter judges: the append response when it
    # failed or nothing was stale, otherwise the first failing deletion (or
    # the append response when every deletion went through).
    def call
      remote = fetch_remote_entity
      return recreate if type_changed?(remote)

      stale = stale_attribute_names(remote)
      response = request(:post, 'attrs', @entity.except('id', 'type'))
      return response unless response.is_a?(Net::HTTPSuccess)

      stale.each do |name|
        deletion = request(:delete, "attrs/#{ERB::Util.url_encode(name)}", nil)
        # 404 = someone else already removed it; that is the desired state.
        next if deletion.is_a?(Net::HTTPSuccess) || deletion.is_a?(Net::HTTPNotFound)

        return deletion
      end
      response
    end

    private

    # The broker's attribute names minus the current local ones.
    def stale_attribute_names(remote)
      return [] if remote.nil?

      remote.keys - NON_ATTRIBUTE_KEYS - @entity.keys
    end

    # The read-back is not sent with our context, so the broker may answer
    # the type as a full IRI (https://datamodels.jp/ns/task/Task) or a
    # prefixed name; the comparison uses the last segment. A missing or
    # unreadable remote type is no reason to recreate.
    def type_changed?(remote)
      return false if remote.nil?

      remote_types = Array(remote['type']).map { |type| type.to_s.split(%r{[#/:]}).last }.compact
      remote_types.any? && !remote_types.include?(@entity['type'])
    end

    # Delete, then create from the full representation. A failed deletion is
    # returned for the Emitter to log (404: already gone, create anyway).
    def recreate
      deletion = request(:delete, nil, nil)
      unless deletion.is_a?(Net::HTTPSuccess) || deletion.is_a?(Net::HTTPNotFound)
        return deletion
      end

      BrokerHttp.request(:post, "#{@connection.api_base}/entities",
                         connection: @connection, token: @connection.auth_token,
                         body: @entity, content_type: 'application/ld+json')
    end

    def fetch_remote_entity
      response = request(:get, nil, nil)
      return nil unless response.is_a?(Net::HTTPSuccess)

      parsed = JSON.parse(response.body)
      parsed.is_a?(Hash) ? parsed : nil
    rescue JSON::ParserError
      nil
    end

    def request(method, subresource, body)
      resource = ["entities/#{@entity['id']}", subresource].compact.join('/')
      BrokerHttp.request(method, "#{@connection.api_base}/#{resource}",
                         connection: @connection, token: @connection.auth_token,
                         body: body, content_type: body ? 'application/ld+json' : nil)
    end
  end
end
