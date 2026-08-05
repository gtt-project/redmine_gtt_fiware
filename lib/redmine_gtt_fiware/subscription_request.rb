require 'json'

module RedmineGttFiware
  # Builds the broker subscription request (endpoints + JSON body) for a
  # subscription template. NgsiV2 and NgsiLd subclass this with the standard's
  # payload shape and API path; SubscriptionRequest.build picks the right one.
  #
  # The broker is pub/sub only (#64): the notification block carries only the
  # callback endpoint and the webhook-auth headers (webhook secret +
  # registration URL). All entity-to-issue mapping happens plugin-side in
  # NotificationProcessor, so no field templating is sent to the broker.
  class SubscriptionRequest
    WEBHOOK_SECRET_HEADER = 'X-Gtt-Webhook-Secret'.freeze
    REGISTRATION_URL_HEADER = 'X-Redmine-GTT-Subscription-Template-URL'.freeze

    # base_url: the Redmine base URL (request.base_url) for callback endpoints.
    def self.build(template, base_url:, throttling: 1)
      klass = template.ngsi_ld? ? NgsiLd : NgsiV2
      klass.new(template, base_url: base_url, throttling: throttling)
    end

    def initialize(template, base_url:, throttling: 1)
      @template = template
      @base_url = base_url
      @throttling = throttling
    end

    # POST target that creates a subscription.
    def subscriptions_url
      "#{api_base}/subscriptions"
    end

    # DELETE target that removes the template's current subscription.
    def subscription_url
      "#{api_base}/subscriptions/#{@template.subscription_id}"
    end

    # Broker entities collection (used by the copy-as-curl helper).
    def entities_url
      "#{api_base}/entities"
    end

    def to_json(*_args)
      JSON.generate(payload)
    end

    # Content type for the subscription POST. NGSI-LD overrides this with
    # application/ld+json because the payload embeds @context.
    def content_type
      'application/json'
    end

    # Tenant headers for broker requests, defined by the connection.
    def tenant_headers
      @template.broker_connection&.tenant_headers || {}
    end

    private

    # The connection URL with the standard's version prefix
    # (BrokerConnection#api_base handles preserving explicit versioned paths).
    def api_base
      @template.broker_connection.api_base
    end

    # Subclasses implement this.
    def payload
      raise NotImplementedError
    end

    # Plain appends, not URI.join with an absolute path: joining "/fiware/..."
    # discards any path in the base, which breaks sub-URI deployments
    # (Setting.host_name may legitimately be "example.com/redmine", #101).
    def callback_url
      "#{@base_url.to_s.chomp('/')}/fiware/subscription_template/#{@template.id}/notification"
    end

    def registration_url
      "#{@base_url.to_s.chomp('/')}/fiware/subscription_template/#{@template.id}/registration/"
    end
  end
end
