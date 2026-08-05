require 'net/http'

module RedmineGttFiware
  # Synchronous v1 of the issue emission pipeline (#69, step 1): pushes core
  # Issue entities to every NGSI-LD connection with an emission mapping for
  # the issue's tracker. Failures are logged, never raised - an unreachable
  # broker must never block saving an issue. This class is the seam for a
  # later job-based backend.
  class Emitter
    # URN-safe slug; anything else counts as unset so a stray value cannot
    # produce malformed entity ids.
    INSTANCE_ID_PATTERN = /\A[A-Za-z0-9_-]+\z/

    class << self
      # Wraps NotificationProcessor issue writes: issues created or updated
      # from broker notifications must not be emitted back (echo loop).
      # Restores the previous value so nested suppress blocks cannot
      # re-enable emission for an outer one.
      #
      # INVARIANT: emission fires from after_commit (IssuePatch), so the
      # commit must happen inside the block. That holds because each save in
      # the block commits its own transaction. Wrapping a whole notification
      # batch in one ActiveRecord::Base.transaction would defer the commits
      # (and the emission callbacks) past the ensure below and silently
      # disable this echo-loop protection - do not add such a transaction.
      def suppress
        previous = Thread.current[:gtt_fiware_suppress_emission]
        Thread.current[:gtt_fiware_suppress_emission] = true
        yield
      ensure
        Thread.current[:gtt_fiware_suppress_emission] = previous
      end

      def suppressed?
        Thread.current[:gtt_fiware_suppress_emission] == true
      end

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
          # 409: the entity exists - EmissionRefresh updates its attributes
          # and deletes the ones the current representation no longer
          # carries (#146).
          if response.is_a?(Net::HTTPConflict)
            response = EmissionRefresh.new(connection, entity).call
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

      # The payload embeds @context (PATCH bodies inherit the entity's), so
      # bodies are declared as JSON-LD. Server-side emission can only use a
      # stored token; a token-less or browser-mode connection emits
      # unauthenticated (fine for open brokers, 401s are logged otherwise).
      def request(connection, method, resource, body = nil)
        BrokerHttp.request(method, "#{connection.api_base}/#{resource}",
                           connection: connection, token: connection.auth_token,
                           body: body, content_type: body ? 'application/ld+json' : nil)
      end

      def log_failure(issue, connection, response)
        Rails.logger.error "[FIWARE] Emission for issue ##{issue.id} to " \
                           "#{connection.name} answered #{response.code}: #{response.body.to_s[0, 200]}"
      end
    end
  end
end
