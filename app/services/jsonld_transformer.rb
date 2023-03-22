class JsonldTransformer
  # Transforms input_data from normalized to non-normalized JSON-LD format
  def self.to_non_normalized(input_data)
    input_data.each_with_object({}) do |(key, value), output_data|
      output_data[key] = process_value(value)
    end
  end

  # Transforms input json_ld data from non-normalized JSON-LD to NGSIv2 format
  def self.to_ngsi_v2(json_ld)
    json_v2 = json_ld.each_with_object({}) do |(key, value), transformed|
      transformed[key] = process_key_value(key, value)
    end
    json_v2.delete(:@context)
    json_v2
  end

  private

  def self.process_value(value)
    return value[:value][:@value] if value.is_a?(Hash) && value[:type] == "Property" && value[:value].is_a?(Hash) && value[:value].has_key?(:@type) && value[:value].has_key?(:@value)
    return value[:object] if value.is_a?(Hash) && value[:type] == "Relationship"
    return value[:value] if value.is_a?(Hash) && value[:type] == "GeoProperty"

    value
  end

  def self.process_key_value(key, value)
    case key
    when 'id', 'type'
      value.gsub('.jsonld', '.json')
    else
      process_non_id_value(value)
    end
  end

  def self.process_non_id_value(value)
    return value.gsub('.jsonld', '.json').gsub('?normalized=false', '') if value.is_a?(String) && value.include?('.jsonld')
    return value unless value.is_a?(Hash) && value.has_key?('type')

    case value['type']
    when 'Property'
      value['value']
    when 'Relationship'
      { 'type' => 'Relationship', 'value' => value['object'].gsub('.jsonld', '.json').gsub('?normalized=false', '') }
    when 'GeoProperty'
      { 'type' => 'geo:json', 'value' => value['value'] }
    else
      value
    end
  end
end
