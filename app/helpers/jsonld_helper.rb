module JsonldHelper
  # Transforms input_data from normalized to non-normalized JSON-LD format
  def self.to_non_normalized(input_data)
    input_data.each_with_object({}) do |(key, value), output_data|
      output_data[key] = process_value(value) # calls process_value method on each value and store it in the output_data hash
    end
  end

  # Transforms input json_ld data from non-normalized JSON-LD to NGSIv2 format
  def self.to_ngsi_v2(json_ld)
    json_v2 = json_ld.each_with_object({}) do |(key, value), transformed|
      transformed[key] = process_key_value(key, value) # calls process_key_value method on each key-value pair and store it in the transformed hash
    end
    json_v2.delete(:@context) # removes the @context key
    json_v2 # return transformed hash
  end

  private

  # method that processes the given value
  def self.process_value(value)
    return value[:value][:@value] if value.is_a?(Hash) && value[:type] == "Property" && value[:value].is_a?(Hash) && value[:value].has_key?(:@type) && value[:value].has_key?(:@value)
    return value[:object] if value.is_a?(Hash) && value[:type] == "Relationship"
    return value[:value] if value.is_a?(Hash) && value[:type] == "GeoProperty"

    value # return value itself if the value doesn't match any of the above condition
  end

  # method that processes the given key-value pair
  def self.process_key_value(key, value)
    case key
    when 'id', 'type'
      value.gsub('.jsonld', '.json') # replace .jsonld with .json for the values of the keys 'id' and 'type'
    else
      process_non_id_value(value) # calls process_non_id_value method on the given value if the key doesn't match 'id' or 'type'
    end
  end

  # method that processes the given value if the key is not 'id' or 'type'
  def self.process_non_id_value(value)
    return value.gsub('.jsonld', '.json').gsub('?normalized=false', '') if value.is_a?(String) && value.include?('.jsonld')
    return value unless value.is_a?(Hash) && value.has_key?('type')

    case value['type']
    when 'Property'
      value['value'] # return the value of 'value' key if the value's 'type' key has a value 'Property'
    when 'Relationship'
      { 'type' => 'Relationship', 'value' => value['object'].gsub('.jsonld', '.json').gsub('?normalized=false', '') } # return hash with type=Relationship and value with modified string if the value's 'type' has a value 'Relationship'
    when 'GeoProperty'
      { 'type' => 'geo:json', 'value' => value['value'] } # return hash with type=geo:json and value as it is if the value's 'type' key has a value 'GeoProperty'
    else
      value # return the value itself if it doesn't match any of the above conditions
    end
  end
end
