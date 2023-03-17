class JsonldTransformer

  # Transforms input_data from normalized to non-normalized JSON-LD format
  def self.to_non_normalized(input_data)
    output_data = {}

    # Iterate through each key-value pair in the input_data
    input_data.each do |key, value|
      # If the value is a Property type
      if value.is_a?(Hash) && value[:type] == "Property"
        # If value is a Property and has a nested value with @type and @value keys
        # Convert it to a non-normalized format by extracting the @value
        if value[:value].is_a?(Hash) && value[:value].has_key?(:@type) && value[:value].has_key?(:@value)
          output_data[key] = value[:value][:@value]
        else
          output_data[key] = value[:value]
        end
      # If the value is a Relationship type, store the object directly
      elsif value.is_a?(Hash) && value[:type] == "Relationship"
        output_data[key] = value[:object]
      # If the value is a GeoProperty type, store the value directly
      elsif value.is_a?(Hash) && value[:type] == "GeoProperty"
        output_data[key] = value[:value]
      else
        # For other types, store the value directly without transformation
        output_data[key] = value
      end
    end

    # Return the transformed non-normalized JSON-LD data
    output_data
  end

  # Transforms input json_ld data from non-normalized JSON-LD to NGSIv2 format
  def self.to_ngsi_v2(json_ld)
    json_v2 = {}

    # Iterate through each key-value pair in the json_ld input data
    json_ld.each do |key, value|
      case key
      when 'id', 'type'
        # Convert JSON-LD extensions to JSON extensions
        json_v2[key] = value.gsub('.jsonld', '.json')
      else
        # Check if the value is a Hash and has a 'type' key
        if value.is_a?(Hash) && value.has_key?('type')
          # Process the value based on its 'type'
          case value['type']
          when 'Property'
            # If it's a Property type, store the value directly
            json_v2[key] = value['value']
          when 'Relationship'
            # If it's a Relationship type, convert to NGSIv2 Relationship format
            json_v2[key] = {
              'type' => 'Relationship',
              'value' => value['object'].gsub('.jsonld', '.json').gsub('?normalized=false', '')
            }
          when 'GeoProperty'
            # If it's a GeoProperty type, convert to NGSIv2 GeoProperty format
            json_v2[key] = {
              'type' => 'geo:json',
              'value' => value['value']
            }
          else
            # For other types, store the value directly without transformation
            json_v2[key] = value
          end
        # Check if the value is a String and has a JSON-LD extension
        elsif value.is_a?(String) && value.include?('.jsonld')
          # Convert JSON-LD extensions to JSON extensions and remove the 'normalized=false' query parameter
          json_v2[key] = value.gsub('.jsonld', '.json').gsub('?normalized=false', '')
        else
          # For other types, store the value directly without transformation
          json_v2[key] = value
        end
      end
    end

    # Delete the @context key as it's not needed in NGSIv2 format
    json_v2.delete(:@context)

    # Return the transformed NGSIv2 data
    json_v2
  end

end
