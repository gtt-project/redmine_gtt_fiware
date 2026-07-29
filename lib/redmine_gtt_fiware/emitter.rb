require 'net/http'

module RedmineGttFiware
  # Synchronous v1 of the issue emission pipeline (#69, step 1): pushes core
  # Issue entities to every NGSI-LD connection with an emission mapping for
  # the issue's tracker. Failures are logged, never raised - an unreachable
  # broker must never block saving an issue. This class is the seam for a
  # later job-based backend.
  class Emitter
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    class << self
      # Wraps NotificationProcessor issue writes: issues created or updated
      # from broker notifications must not be emitted back (echo loop).
      def suppress
        Thread.current[:gtt_fiware_suppress_emission] = true
        yield
      ensure
        Thread.current[:gtt_fiware_suppress_emission] = nil
      end

      def suppressed?
        Thread.current[:gtt_fiware_suppress_emission] == true
      end

      # URN-safe slug; anything else counts as unset so a stray value cannot
      # produce malformed entity ids.
      INSTANCE_ID_PATTERN = /\A[A-Za-z0-9_-]+\z/

      # The instance identifier baked into every emitted URN. Emission is off
      # until the admin sets it (and it must stay stable once set - changing
      # it re-identifies every emitted entity).
      def instance_id
        value = RedmineGttFiware.settings['fiware_instance_id'].to_s.strip
        value.match?(INSTANCE_ID_PATTERN) ? value : ''
      end

      def upsert(issue)
        each_emission(issue) do |mapping, connection|
          entity = IssueEntity.new(issue, mapping).to_h
          response = request(connection, :post, 'entities', entity)
          # 409: the entity exists - update its attributes instead. The id
          # and type are immutable and must not be in the PATCH body.
          if response.is_a?(Net::HTTPConflict)
            attrs = entity.except('id', 'type')
            response = request(connection, :patch, "entities/#{entity['id']}/attrs", attrs)
          end
          log_failure(issue, connection, response) unless response.is_a?(Net::HTTPSuccess)
        end
      end

      def delete(issue)
        each_emission(issue) do |_mapping, connection|
          response = request(connection, :delete, "entities/#{IssueEntity.urn(issue)}")
          # 404 = never emitted or already gone; not a failure.
          unless response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPNotFound)
            log_failure(issue, connection, response)
          end
        end
      end

      private

      # Yields each applicable (mapping, connection) pair, guarding the whole
      # pipeline: cheapest checks first, and every broker call isolated so one
      # failing connection neither raises nor blocks the others.
      def each_emission(issue)
        return if instance_id.blank?
        return if suppressed?
        return if issue.is_private?
        return unless issue.project&.module_enabled?(:gtt_fiware_emission)

        EmissionMapping.where(tracker_id: issue.tracker_id)
                       .includes(:broker_connection).find_each do |mapping|
          connection = mapping.broker_connection
          next unless connection&.ngsi_ld?

          begin
            yield mapping, connection
          rescue StandardError => e
            Rails.logger.error "[FIWARE] Emission for issue ##{issue.id} to " \
                               "#{connection.name} failed: #{e.class}: #{e.message}"
          end
        end
      end

      def request(connection, method, resource, body = nil)
        uri = URI(connection.url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        klass = { post: Net::HTTP::Post, patch: Net::HTTP::Patch, delete: Net::HTTP::Delete }.fetch(method)
        req = klass.new("#{ld_path(uri)}/#{resource}", headers(connection, body))
        req.body = body.to_json if body
        http.request(req)
      end

      # The payload embeds @context (PATCH bodies inherit the entity's), so
      # bodies are declared as JSON-LD. Server-side emission can only use a
      # stored token; a token-less or browser-mode connection emits
      # unauthenticated (fine for open brokers, 401s are logged otherwise).
      def headers(connection, body)
        result = {}
        result['Content-Type'] = 'application/ld+json' if body
        result['NGSILD-Tenant'] = connection.fiware_service if connection.fiware_service.present?
        pair = connection.token_header_pair(connection.auth_token)
        result[pair.first] = pair.last if pair
        result
      end

      # Preserve an explicit /ngsi-ld/v1 path in the connection URL, append
      # the default prefix otherwise (same convention as SubscriptionRequest).
      def ld_path(uri)
        path = uri.path.chomp('/')
        path.match?(%r{/ngsi-ld/v1\z}) ? path : "#{path}/ngsi-ld/v1"
      end

      def log_failure(issue, connection, response)
        Rails.logger.error "[FIWARE] Emission for issue ##{issue.id} to " \
                           "#{connection.name} answered #{response.code}: #{response.body.to_s[0, 200]}"
      end
    end
  end
end
