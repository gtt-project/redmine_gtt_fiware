module RedmineGttFiware
  class SubscriptionRequest
    # Builds an NGSI-LD subscription (`/ngsi-ld/v1/subscriptions`). The LD shape
    # differs from NGSIv2: the selector fields sit at the top level (`entities`,
    # `q`, `geoQ`, `watchedAttributes`), change filtering uses
    # `notificationTrigger` (not `alterationTypes`), the callback is
    # `notification.endpoint` with `receiverInfo` headers, and JSON-LD terms are
    # resolved through `@context`.
    #
    # `notification.format` is `normalized` so entities arrive in
    # Property/Relationship/GeoProperty form, which Entity#from_ngsi_ld expects.
    class NgsiLd < SubscriptionRequest
      private

      # Preserve an explicit /ngsi-ld/v1/-style path in the broker URL,
      # otherwise default to the standard prefix.
      def version_path
        path = broker_uri.path
        path.match(%r{/ngsi-ld/v\d+/}) ? path : '/ngsi-ld/v1/'
      end

      def payload
        payload = {
          type: 'Subscription',
          description: @template.name,
          entities: @template.entities,
          notification: notification,
          isActive: @template.status == 'active',
          throttling: @throttling
        }

        payload[:id] = @template.subscription_id if @template.subscription_id.present?
        payload['@context'] = ld_context if ld_context
        payload[:watchedAttributes] = parsed_attrs if parsed_attrs.present?
        payload[:q] = @template.expression_query if @template.expression_query.present?
        payload[:geoQ] = geo_q if geo_q
        triggers = @template.notification_triggers
        payload[:notificationTrigger] = triggers if triggers.present?
        payload[:expiresAt] = expires_at if expires_at

        payload
      end

      def notification
        {
          format: 'normalized',
          endpoint: {
            uri: callback_url,
            accept: 'application/json',
            receiverInfo: [
              { key: WEBHOOK_SECRET_HEADER, value: @template.webhook_secret },
              { key: REGISTRATION_URL_HEADER, value: registration_url }
            ]
          }
        }
      end

      def geo_q
        return nil unless @template.expression_georel.present? &&
                          @template.expression_geometry.present? &&
                          @template.expression_coords.present?

        {
          georel: @template.expression_georel,
          geometry: @template.expression_geometry,
          coordinates: @template.expression_coords
        }
      end

      # @context may be a single URL or a JSON array/object of contexts. Parse
      # it when it is JSON, otherwise pass the URL string through unchanged.
      def ld_context
        raw = @template.context.to_s.strip
        return nil if raw.empty?

        JSON.parse(raw)
      rescue JSON::ParserError
        raw
      end

      def parsed_attrs
        return nil if @template.attrs.blank?

        JSON.parse(@template.attrs)
      rescue JSON::ParserError
        nil
      end

      def expires_at
        return nil if @template.expires.blank?

        @template.expires.respond_to?(:iso8601) ? @template.expires.iso8601 : @template.expires.to_s
      end
    end
  end
end
