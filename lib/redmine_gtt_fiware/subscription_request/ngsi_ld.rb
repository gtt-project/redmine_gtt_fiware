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
      # The template stores NGSIv2 geometry names (SubscriptionTemplate::
      # GEOMETRIES); NGSI-LD geoQ.geometry takes GeoJSON type names. `box` has
      # no NGSI-LD equivalent and passes through verbatim, so the broker
      # rejects it with a clear error instead of the plugin guessing a shape.
      GEOMETRY_TYPE_MAP = {
        'point' => 'Point',
        'line' => 'LineString',
        'polygon' => 'Polygon'
      }.freeze

      # The payload embeds @context, which NGSI-LD requires to be declared as
      # JSON-LD content.
      def content_type
        'application/ld+json'
      end

      private

      # An explicit /ngsi-ld/v1-style path in the broker URL is preserved by
      # SubscriptionRequest#version_path; otherwise the standard prefix.
      def default_version_path
        '/ngsi-ld/v1/'
      end

      def versioned_path_pattern
        %r{/ngsi-ld/v\d+(/|\z)}
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

        geometry = @template.expression_geometry
        {
          georel: @template.expression_georel,
          geometry: GEOMETRY_TYPE_MAP.fetch(geometry, geometry),
          coordinates: @template.expression_coords
        }
      end

      # @context may be a single URL or a JSON array/object of contexts. Parse
      # it when it is JSON, otherwise pass the URL string through unchanged.
      # The template's own context overrides the connection's default.
      def ld_context
        raw = @template.effective_context.to_s.strip
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
