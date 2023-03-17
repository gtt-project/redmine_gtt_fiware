class JsonldTransformer

  def self.to_non_normalized(input_data)
    output_data = {}
    input_data.each do |key, value|
      if value.is_a?(Hash) && value[:type] == "Property"
        if value[:value].is_a?(Hash) && value[:value].has_key?(:@type) && value[:value].has_key?(:@value)
          output_data[key] = value[:value][:@value]
        else
          output_data[key] = value[:value]
        end
      elsif value.is_a?(Hash) && value[:type] == "Relationship"
        output_data[key] = value[:object]
      elsif value.is_a?(Hash) && value[:type] == "GeoProperty"
        output_data[key] = value[:value]
      else
        output_data[key] = value
      end
    end
    output_data
  end

  # Transforms from non-normalized JSON-LD tp NGSIv2
  def self.to_ngsi_v2(json_ld)
    json_v2 = {}

    json_ld.each do |key, value|
      case key
      when 'id', 'type'
        json_v2[key] = value.gsub('.jsonld', '.json')
      else
        if value.is_a?(Hash) && value.has_key?('type')
          case value['type']
          when 'Property'
            json_v2[key] = value['value']
          when 'Relationship'
            json_v2[key] = { 'type' => 'Relationship', 'value' => value['object'].gsub('.jsonld', '.json').gsub('?normalized=false', '') }
          when 'GeoProperty'
            json_v2[key] = { 'type' => 'geo:json', 'value' => value['value'] }
          else
            json_v2[key] = value
          end
        elsif value.is_a?(String) && value.include?('.jsonld')
          json_v2[key] = value.gsub('.jsonld', '.json').gsub('?normalized=false', '')
        else
          json_v2[key] = value
        end
      end
    end

    # Delete this key as it's not needed in NGSIv2
    json_v2.delete(:@context)

    json_v2
  end

end
