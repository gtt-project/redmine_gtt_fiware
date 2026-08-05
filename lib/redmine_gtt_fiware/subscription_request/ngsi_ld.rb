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

      def payload
        payload = {
          type: 'Subscription',
          description: @template.name,
          entities: @template.entities,
          notification: notification,
          isActive: @template.status == 'active'
        }

        # CIM 009 requires throttling "greater than 0"; 0 means "no
        # throttling" in this plugin and is expressed by omitting the field.
        payload[:throttling] = @throttling if @throttling.to_i.positive?
        payload[:id] = @template.subscription_id if @template.subscription_id.present?
        payload['@context'] = ld_context if ld_context
        payload[:watchedAttributes] = parsed_attrs if parsed_attrs.present?
        payload[:q] = @template.expression_query if @template.expression_query.present?
        payload[:geoQ] = geo_q if geo_q
        triggers = @template.notification_triggers
        payload[:notificationTrigger] = triggers if triggers.present?
        payload[:expiresAt] = expires_utc if expires_utc

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

      # The stored geo filter uses NGSIv2 syntax (the form and the Area
      # picker write it, and it predates LD support): georel `coveredBy`,
      # near modifiers with `:`, and coordinates as "lat,lon;lat,lon" pairs.
      # NGSI-LD (CIM 009 clause 4.10 / Table 5.2.13-1) has no coveredBy
      # (within is the equivalent), near modifiers use `==`, and coordinates
      # are a GeoJSON coordinates array in lon,lat order. Translate here so
      # the same stored triple publishes correctly to both standards.
      GEOREL_MAP = { 'coveredBy' => 'within' }.freeze

      def geo_q
        return nil unless @template.expression_georel.present? &&
                          @template.expression_geometry.present? &&
                          @template.expression_coords.present?

        geometry = @template.expression_geometry
        {
          georel: ld_georel(@template.expression_georel),
          geometry: GEOMETRY_TYPE_MAP.fetch(geometry, geometry),
          coordinates: ld_coordinates(@template.expression_coords, geometry)
        }
      end

      def ld_georel(georel)
        base, modifier = georel.to_s.split(';', 2)
        base = GEOREL_MAP.fetch(base, base)
        return base if modifier.nil?

        "#{base};#{modifier.sub(/\A(maxDistance|minDistance):/, '\1==')}"
      end

      # v2 pair syntax converts to the GeoJSON nesting for the geometry
      # type; anything else (including box, which NGSI-LD does not have)
      # passes through verbatim so the broker reports it instead of the
      # plugin guessing.
      def ld_coordinates(coords, geometry)
        pairs = v2_coordinate_pairs(coords)
        return coords if pairs.nil?

        case geometry
        when 'point' then pairs.first
        when 'line' then pairs
        when 'polygon' then [pairs]
        else coords
        end
      end

      # "lat1,lon1;lat2,lon2" (the v2/Orion order) as [[lon, lat], ...]
      # (GeoJSON order), or nil when the string is not that syntax.
      def v2_coordinate_pairs(coords)
        number = /\A-?\d+(\.\d+)?\z/
        coords.to_s.strip.split(';').map do |pair|
          lat, lon, extra = pair.split(',').map(&:strip)
          return nil unless extra.nil? && lat&.match?(number) && lon&.match?(number)

          [Float(lon), Float(lat)]
        end.presence
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

    end
  end
end
