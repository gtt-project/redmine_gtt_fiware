class JsonldTransformer

  def self.to_non_normalized_format(input_data)
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

end
