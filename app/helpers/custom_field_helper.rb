# CustomFieldHelper is a utility module to handle the processing of custom fields
# for Redmine issues and projects in JSON-LD format.
module CustomFieldHelper
  # Converts a string to camelCase and prepends "cf_"
  #
  # @param str [String] the input string
  # @return [String] the camelCase string with "cf_" prepended
  def self.camel_case(str)
    "cf_" + str.split(' ').map.with_index { |word, index| index.zero? ? word.downcase : word.capitalize }.join
  end

  # Converts a string to snake_case and prepends "cf_"
  #
  # @param str [String] the input string
  # @return [String] the snake_case string with "cf_" prepended
  def self.snake_case(str)
    "cf_" + str.downcase.gsub(' ', '_')
  end

  # Processes custom fields and adds them to the given JSON object
  #
  # @param json [Hash] the JSON object to update with custom field values
  # @param custom_field_values [Array] an array of custom field values
  # @param normalized [Boolean] the flag to determine if the output should be normalized
  def self.process_custom_fields(json, custom_field_values, view_context, normalized)
    custom_field_values.each do |cf|
      # Generate the JSON key using camelCase format
      key = camel_case(cf.custom_field.name)

      # puts cf.inspect

      # Process custom field values based on their field_format
      case cf.custom_field.field_format
      when 'string', 'text'
        json[key] = {
          "type": 'Property',
          "value": cf.value
        }
      when 'version', 'link', 'attachment'
        json[key] = {
          "type": 'Property',
          "value": cf.value.empty? ? nil : cf.value
        }
      when 'list', 'enumeration'
        json[key] = {
          "type": 'Property',
          "value": cf.value.is_a?(Array) && cf.value.first.empty? || cf.value.is_a?(String) && cf.value.empty? ? nil : cf.value
        }
      when 'user'
        json[key] = {
          "type": 'Relationship',
          "object": cf.value.present? ? nil : view_context.url_for(controller: 'users', action: 'show', id: cf.value, only_path: false, format: :jsonld, normalized: normalized)
        }
      when 'bool'
        json[key] = {
          "type": 'Property',
          "value": cf.value == '1' ? true : (cf.value == '0' ? false : nil)
        }
      when 'int'
        json[key] = {
          "type": 'Property',
          "value": cf.value.empty? ? nil : cf.value.to_i
        }
      when 'float'
        json[key] = {
          "type": 'Property',
          "value": cf.value.empty? ? nil : cf.value.to_f
        }
      when 'date'
        json[key] = {
          "type": 'Property',
          "value": {
            "@type": 'Date',
            "@value": cf.value.empty? ? nil : cf.value
          }
        }
      end
    end
  end
end
