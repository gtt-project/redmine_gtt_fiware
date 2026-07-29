module RedmineGttFiware
  # Serializes an issue into the frozen core Issue entity (#69, step 1).
  # Deliberately minimal: this property set is the cross-instance interop
  # contract, so nothing gets added here casually. Admin-exposable standard
  # fields and custom fields arrive with design step 2.
  class IssueEntity
    CORE_CONTEXT = 'https://uri.etsi.org/ngsi-ld/v1/ngsi-ld-core-context.jsonld'.freeze

    # Stable across any reconfiguration (subtype renames never change ids);
    # the federation keystone (#70).
    def self.urn(issue)
      "urn:ngsi-ld:Issue:redmine:#{Emitter.instance_id}:#{issue.id}"
    end

    def initialize(issue, mapping)
      @issue = issue
      @mapping = mapping
    end

    def to_h
      entity = {
        'id' => self.class.urn(@issue),
        'type' => 'Issue',
        'title' => property(@issue.subject),
        # Normalized lifecycle value for cross-instance consumers; the
        # instance's own status name travels alongside as statusLabel.
        'status' => property(@issue.status.is_closed? ? 'closed' : 'open'),
        'statusLabel' => property(@issue.status.name),
        'subtype' => property(@mapping.subtype),
        'dateCreated' => datetime_property(@issue.created_on),
        'dateModified' => datetime_property(@issue.updated_on),
        '@context' => CORE_CONTEXT
      }
      entity['source'] = property(source_url) if source_url
      entity['location'] = geo_property if geometry?
      entity['refersTo'] = relationship(@issue.fiware_entity) if refers_to?
      entity
    end

    private

    def property(value)
      { 'type' => 'Property', 'value' => value }
    end

    def datetime_property(time)
      { 'type' => 'Property',
        'value' => { '@type' => 'DateTime', '@value' => time.utc.iso8601 } }
    end

    def relationship(object)
      { 'type' => 'Relationship', 'object' => object }
    end

    def geometry?
      @issue.respond_to?(:geom) && @issue.geom.present?
    end

    def geo_property
      { 'type' => 'GeoProperty', 'value' => strip_zero_z(RGeo::GeoJSON.encode(@issue.geom)) }
    end

    # GTT stores every geometry in a Z-enabled factory, so 2D data encodes
    # with a zero third coordinate - and some brokers (GeonicDB) validate
    # positions as strict [lon, lat] pairs. The zero-Z artifact is stripped;
    # a real altitude is kept, since RFC 7946 allows it (brokers that reject
    # 3D get a logged failure, not silently flattened data).
    def strip_zero_z(geojson)
      case geojson
      when Hash
        geojson.transform_values { |value| strip_zero_z(value) }
      when Array
        if geojson.length == 3 && geojson.all? { |c| c.is_a?(Numeric) } && geojson[2].zero?
          geojson[0, 2]
        else
          geojson.map { |value| strip_zero_z(value) }
        end
      else
        geojson
      end
    end

    # NGSI-LD Relationship objects must be URIs; issues created before the
    # notification pipeline stored entity ids, or with hand-edited values,
    # may hold something else - omit rather than fail the whole entity.
    def refers_to?
      @issue.fiware_entity.present? && @issue.fiware_entity.match?(/\A\w+:\S+\z/)
    end

    # The issue's canonical URL, from the configured host (same source as
    # email links and the callback URLs, #101). Omitted when unconfigured.
    def source_url
      host = Setting.host_name.to_s.strip
      return nil if host.blank?

      "#{Setting.protocol}://#{host}/issues/#{@issue.id}"
    end
  end
end
