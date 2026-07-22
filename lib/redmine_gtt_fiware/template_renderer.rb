module RedmineGttFiware
  # Renders a template string against a normalized Entity, substituting
  # `${path}` expressions (see Entity#resolve for the path syntax). Unknown
  # paths render as an empty string so a missing attribute never raises or
  # leaves a literal `${...}` in the output.
  module TemplateRenderer
    EXPRESSION = /\$\{([^}]+)\}/

    module_function

    # Renders scalar text (subject, description, notes). Returns nil for a nil
    # template so an absent optional field stays absent.
    def render(template, entity)
      return nil if template.nil?

      template.to_s.gsub(EXPRESSION) do
        value = entity.resolve(Regexp.last_match(1))
        stringify(value)
      end
    end

    # Renders a value into a GeoJSON geometry for the issue. The template's
    # geometry field is a GeoJSON structure whose leaves may reference the
    # entity (typically `${location}` or `${attrs.location.value}`). A path that
    # resolves to a geometry hash is substituted structurally, not stringified,
    # so the result stays valid GeoJSON.
    def render_geometry(template_geometry, entity)
      return nil if template_geometry.nil?

      substitute_structure(template_geometry, entity)
    end

    def stringify(value)
      case value
      when nil then ''
      when String then value
      else value.to_json
      end
    end

    # Walks a parsed-JSON structure. A string that is exactly one `${path}`
    # expression is replaced by the resolved value (preserving hashes/arrays);
    # a string with surrounding text is rendered as text.
    def substitute_structure(node, entity)
      case node
      when Hash
        node.each_with_object({}) { |(k, v), out| out[k] = substitute_structure(v, entity) }
      when Array
        node.map { |v| substitute_structure(v, entity) }
      when String
        whole = node.match(/\A\$\{([^}]+)\}\z/)
        whole ? entity.resolve(whole[1]) : render(node, entity)
      else
        node
      end
    end
  end
end
