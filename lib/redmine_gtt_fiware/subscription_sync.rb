module RedmineGttFiware
  # Reconciles a template's local state with the broker's (#13):
  #
  #   broker answers 404 -> the subscription is gone (a oneshot fired, or it
  #                         expired and was purged); clear the stored id.
  #   broker answers 200 -> map the reported status onto the local one.
  #
  # Returns the message key for the user-facing outcome; the caller
  # translates. A 200 whose status the plugin cannot interpret, and a local
  # update that fails validation, are reported as errors rather than as a
  # successful sync.
  class SubscriptionSync
    def initialize(template, subscription_request:, token:)
      @template = template
      @request = subscription_request
      @token = token
    end

    def call
      return :subscription_sync_no_subscription if @template.subscription_id.blank?

      response = fetch_remote_subscription
      case response
      when Net::HTTPNotFound
        clear_subscription_id
      when Net::HTTPSuccess
        apply_remote_status(JSON.parse(response.body))
      else
        Rails.logger.error "FIWARE broker sync failed: #{response.code} #{response.message}"
        :subscription_sync_error
      end
    rescue JSON::ParserError
      Rails.logger.error 'FIWARE broker sync returned an unparsable body'
      :subscription_sync_error
    rescue StandardError => e
      Rails.logger.error "Error syncing subscription: #{e.message}"
      :subscription_sync_error
    end

    private

    def fetch_remote_subscription
      BrokerHttp.request(:get, @request.subscription_url,
                         connection: @template.broker_connection, token: @token)
    end

    def clear_subscription_id
      return :subscription_sync_removed if @template.update(subscription_id: nil)

      Rails.logger.error 'FIWARE broker sync: clearing the removed subscription failed: ' \
                         "#{@template.errors.full_messages.join(', ')}"
      :subscription_sync_error
    end

    # Maps the broker's reported subscription state onto the local status.
    # NGSIv2 reports status active/inactive/oneshot/expired/failed ('failed'
    # means the last notification failed but the subscription is still
    # active); NGSI-LD reports status active/paused/expired plus isActive.
    def apply_remote_status(subscription)
      remote = subscription['status'].to_s
      if remote.empty? && @template.ngsi_ld? && subscription.key?('isActive')
        remote = subscription['isActive'] == false ? 'paused' : 'active'
      end

      normalized =
        case remote
        when 'active', 'inactive', 'oneshot' then remote
        when 'failed' then 'active'
        when 'paused', 'expired' then 'inactive'
        end
      if normalized.nil?
        Rails.logger.error 'FIWARE broker sync: unrecognized subscription status in response'
        return :subscription_sync_error
      end

      unless normalized == @template.status
        return :subscription_sync_error unless @template.update(status: normalized)
      end
      :subscription_synced
    end
  end
end
