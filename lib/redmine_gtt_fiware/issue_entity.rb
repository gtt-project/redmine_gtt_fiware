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
        'dateModified' => datetime_property(@issue.updated_on)
      }
      entity['source'] = property(source_url) if source_url
      entity['location'] = geo_property if geometry?
      entity['refersTo'] = relationship(@issue.fiware_entity) if refers_to?
      entity.merge!(exposed_properties)
      entity.merge!(exposed_custom_properties)
      entity['@context'] = entity_context
      entity
    end

    private

    # The admin-exposed standard fields (#69, step 2b): each renderer returns
    # the NGSI-LD attribute or nil when the issue has no value, so absent
    # data is absent from the entity instead of null-valued.
    def exposed_properties
      @mapping.exposed_standard_fields.each_with_object({}) do |field, result|
        value = send("exposed_#{field.underscore}")
        result[field] = value if value
      end
    end

    def exposed_description
      property(@issue.description) if @issue.description.present?
    end

    def exposed_priority
      property(@issue.priority.name) if @issue.priority
    end

    def exposed_category
      property(@issue.category.name) if @issue.category
    end

    def exposed_target_version
      property(@issue.fixed_version.name) if @issue.fixed_version
    end

    def exposed_start_date
      date_property(@issue.start_date) if @issue.start_date
    end

    def exposed_due_date
      date_property(@issue.due_date) if @issue.due_date
    end

    def exposed_estimated_time
      property(@issue.estimated_hours) if @issue.estimated_hours
    end

    def exposed_percent_done
      property(@issue.done_ratio.to_i)
    end

    # A Relationship to the parent issue's URN - resolvable when the parent
    # is emitted too, and still a truthful stable identifier when not.
    def exposed_parent
      relationship(self.class.urn(@issue.parent)) if @issue.parent
    end

    # Publishing person names to a shared broker is an explicit admin
    # decision (the checkbox defaults off like everything else).
    def exposed_assignee
      property(@issue.assigned_to.name) if @issue.assigned_to
    end

    # The admin-exposed custom fields (#69, step 2c), typed by field format;
    # blank values are absent from the entity like everything else.
    def exposed_custom_properties
      @mapping.exposed_custom_fields.each_with_object({}) do |(cf_id, term), result|
        custom_field = IssueCustomField.find_by(id: cf_id)
        next unless custom_field

        value = custom_property(custom_field)
        result[term] = value if value
      end
    end

    def custom_property(custom_field)
      raw = @issue.custom_field_value(custom_field)
      raw = raw.reject(&:blank?) if raw.is_a?(Array)
      return nil if raw.blank? && raw != false

      case custom_field.field_format
      when 'int' then property(raw.to_i)
      when 'float' then property(raw.to_f)
      when 'bool' then property(raw == '1' || raw == true)
      when 'date'
        begin
          date_property(Date.parse(raw.to_s))
        rescue ArgumentError, TypeError
          nil
        end
      else
        property(raw.is_a?(Array) ? raw.map(&:to_s) : raw.to_s)
      end
    end

    def property(value)
      { 'type' => 'Property', 'value' => value }
    end

    def date_property(date)
      { 'type' => 'Property',
        'value' => { '@type' => 'Date', '@value' => date.iso8601 } }
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

    # Brokers dereference @context at ingestion, so the instance's published
    # context (#69, step 2) is referenced only when the instance has a public
    # identity (Setting.host_name) a broker can actually reach; an
    # unconfigured instance emits with the core context alone and its terms
    # expand into the default vocabulary.
    def entity_context
      host = Setting.host_name.to_s.strip
      return CORE_CONTEXT if host.blank?

      ["#{Setting.protocol}://#{host}/fiware/context.jsonld", CORE_CONTEXT]
    end
  end
end
