module RedmineGttFiware
  # A broker entity, normalized to a uniform shape so the same plugin-side
  # templating and issue-mapping pipeline works for both NGSI-LD and NGSIv2.
  #
  # After normalization an entity is:
  #   - id, type      : strings
  #   - attributes     : { "<name>" => { "value" => <scalar/hash>, "type" => "...", ... } }
  #   - geometry       : GeoJSON geometry hash (from the location GeoProperty), or nil
  #
  # NGSI-LD attributes look like { "type" => "Property"|"Relationship"|"GeoProperty",
  # "value"|"object" => ... }; NGSIv2 attributes look like { "type" => ...,
  # "value" => ..., "metadata" => ... }. Both collapse to a common { "value", "type" }.
  class Entity
    RESERVED_KEYS = %w[id type @context].freeze
    LOCATION_ATTRIBUTE = 'location'.freeze

    attr_reader :id, :type, :attributes, :geometry

    # standard: 'NGSI-LD' or 'NGSIv2' (case-insensitive)
    def self.from(entity, standard)
      normalized = entity.is_a?(Hash) ? entity : {}
      if standard.to_s.casecmp('NGSI-LD').zero?
        from_ngsi_ld(normalized)
      else
        from_ngsi_v2(normalized)
      end
    end

    def self.from_ngsi_ld(entity)
      attributes = {}
      geometry = nil
      entity.each do |key, raw|
        next if RESERVED_KEYS.include?(key)
        next unless raw.is_a?(Hash)

        value = raw.key?('object') ? raw['object'] : raw['value']
        attributes[key] = { 'value' => value, 'type' => raw['type'] }
        geometry ||= raw['value'] if geo_property?(key, raw)
      end
      new(id: entity['id'], type: entity['type'], attributes: attributes, geometry: geometry)
    end

    def self.from_ngsi_v2(entity)
      attributes = {}
      geometry = nil
      entity.each do |key, raw|
        next if %w[id type].include?(key)
        next unless raw.is_a?(Hash)

        attributes[key] = { 'value' => raw['value'], 'type' => raw['type'], 'metadata' => raw['metadata'] }
        geometry ||= raw['value'] if geo_json?(key, raw)
      end
      new(id: entity['id'], type: entity['type'], attributes: attributes, geometry: geometry)
    end

    # A typed GeoProperty is always geometry. Falling back on the attribute name
    # alone would capture a plain `location` Property whose value is a scalar
    # (e.g. "indoors"), so the name-based match additionally requires the value
    # to look like GeoJSON. Combined with the caller's `||=` (first geometry
    # wins), this keeps a real GeoProperty from being shadowed by such a value.
    def self.geo_property?(key, raw)
      raw['type'].to_s == 'GeoProperty' || (key == LOCATION_ATTRIBUTE && geo_json_value?(raw['value']))
    end

    def self.geo_json?(key, raw)
      raw['type'].to_s == 'geo:json' || (key == LOCATION_ATTRIBUTE && geo_json_value?(raw['value']))
    end

    # A minimal GeoJSON geometry check: a hash with a type and coordinates.
    def self.geo_json_value?(value)
      value.is_a?(Hash) && value['type'].present? && value.key?('coordinates')
    end

    def initialize(id:, type:, attributes:, geometry: nil)
      @id = id
      @type = type
      @attributes = attributes || {}
      @geometry = geometry
    end

    # Resolves a template path against the entity. Supported forms:
    #   id, type
    #   attrs.<name>.value  /  <name>.value
    #   attrs.<name>        /  <name>          (shorthand for the value)
    #   attrs.<name>.<key>  (e.g. metadata.unitCode on NGSIv2)
    # Returns nil for an unknown path (callers coerce to "" for output).
    def resolve(path)
      segments = path.to_s.strip.split('.')
      return nil if segments.empty?

      case segments.first
      when 'id' then return @id
      when 'type' then return @type
      end

      segments = segments.drop(1) if segments.first == 'attrs'
      name = segments.shift
      attribute = @attributes[name]
      return nil if attribute.nil?

      # bare `<name>` is shorthand for the value
      return attribute['value'] if segments.empty?
      # `<name>.value` and deeper (metadata, etc.)
      dig_value(attribute, segments)
    end

    private

    def dig_value(node, segments)
      segments.reduce(node) do |current, segment|
        return nil unless current.is_a?(Hash)

        current[segment]
      end
    end
  end
end
