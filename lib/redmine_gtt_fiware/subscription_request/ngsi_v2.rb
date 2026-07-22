module RedmineGttFiware
  class SubscriptionRequest
    # Builds an NGSIv2 subscription (Orion `/v2/subscriptions`). Since #64 the
    # httpCustom block carries only the callback URL and auth headers; the
    # `json` field-templating block is gone (the plugin renders fields itself).
    class NgsiV2 < SubscriptionRequest
      private

      # An explicit versioned path in the broker URL (e.g. /orion/v2.1) is
      # preserved by SubscriptionRequest#version_path; otherwise /v2/.
      def default_version_path
        '/v2/'
      end

      def versioned_path_pattern
        %r{/v2\.\d+(/|\z)}
      end

      def payload
        payload = {
          description: CGI.escape(@template.name),
          subject: {
            entities: @template.entities,
            condition: {
              notifyOnMetadataChange: @template.notify_on_metadata_change
            }
          },
          notification: {
            attrsFormat: 'normalized',
            metadata: ['dateCreated', '*'],
            onlyChangedAttrs: false,
            covered: false,
            httpCustom: http_custom
          },
          throttling: @throttling,
          status: @template.status
        }

        payload[:id] = @template.subscription_id if @template.subscription_id.present?
        payload[:expires] = @template.expires if @template.expires.present?

        condition = payload[:subject][:condition]
        condition[:expression] = expression if expression.present?
        condition[:attrs] = parsed_attrs if parsed_attrs.present?
        condition[:alterationTypes] = @template.alteration_types if @template.alteration_types.present?

        payload
      end

      def http_custom
        {
          url: callback_url,
          headers: {
            'Content-Type' => 'application/json',
            WEBHOOK_SECRET_HEADER => @template.webhook_secret,
            REGISTRATION_URL_HEADER => registration_url
          },
          method: 'POST'
        }
      end

      def expression
        expression = {}
        if @template.expression_georel.present? &&
           @template.expression_geometry.present? &&
           @template.expression_coords.present?
          expression[:georel] = @template.expression_georel
          expression[:geometry] = @template.expression_geometry
          expression[:coords] = @template.expression_coords
        end
        expression[:q] = @template.expression_query if @template.expression_query.present?
        expression
      end

      def parsed_attrs
        return nil if @template.attrs.blank?

        JSON.parse(@template.attrs)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
