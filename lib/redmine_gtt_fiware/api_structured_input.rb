module RedmineGttFiware
  # Converts the REST API's structured inputs into the *_string form inputs
  # the model validates (#22). API clients naturally send structures where
  # the form sends JSON strings (the textareas are a UI detail): entities,
  # attachments and geometry as objects and arrays, attrs as an array of
  # names. Converting them here keeps validation in one place; the converted
  # values are re-parsed and shape-checked by the model before landing in
  # the serialized columns, so this is not a mass-assignment path.
  module ApiStructuredInput
    STRUCTURED_FIELDS = {
      entities: :entities_string,
      attachments: :attachments_string,
      geometry: :geometry_string
    }.freeze

    module_function

    # Mutates the given ActionController::Parameters (or hash) in place.
    # Parameters have indifferent access; a plain Hash may carry either key
    # form, so both are looked up.
    def normalize!(attributes)
      return unless attributes.respond_to?(:key?)

      STRUCTURED_FIELDS.each do |structured, string_field|
        key = [structured, structured.to_s].detect { |candidate| attributes.key?(candidate) }
        next if key.nil?

        value = attributes.delete(key)
        # An explicit null carries no structure to convert; leave whatever
        # the client sent in the *_string field alone.
        next if value.nil?

        attributes[string_field] = json_input(value)
      end

      attrs_key = [:attrs, 'attrs'].detect { |candidate| attributes[candidate].is_a?(Array) }
      attributes[attrs_key] = plain_structure(attributes[attrs_key]).to_json if attrs_key
      attributes
    end

    # The model parses the *_string fields as JSON. A structure is dumped; a
    # string that already is JSON passes through; anything else is a scalar
    # template value and gets encoded as the JSON string it stands for, so
    # geometry: "${location}" works as documented instead of failing to
    # parse.
    def json_input(value)
      return plain_structure(value).to_json unless value.is_a?(String)

      JSON.parse(value)
      value
    rescue JSON::ParserError
      value.to_json
    end

    def plain_structure(value)
      case value
      when ActionController::Parameters then value.to_unsafe_h
      when Array then value.map { |element| plain_structure(element) }
      else value
      end
    end
  end
end
