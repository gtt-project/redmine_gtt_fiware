require 'cgi'
require 'json'
require 'uri'

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
      broker_uri.merge("#{version_path}subscriptions").to_s
    end

    # DELETE target that removes the template's current subscription.
    def subscription_url
      broker_uri.merge("#{version_path}subscriptions/#{@template.subscription_id}").to_s
    end

    # Broker entities collection (used by the copy-as-curl helper).
    def entities_url
      broker_uri.merge("#{version_path}entities").to_s
    end

    def to_json(*_args)
      JSON.generate(payload)
    end

    private

    # Preserve an explicit versioned API path in the broker URL, with or
    # without a trailing slash (normalized to end with one), otherwise fall
    # back to the standard's default prefix.
    def version_path
      path = broker_uri.path
      return default_version_path unless path.match?(versioned_path_pattern)

      path.end_with?('/') ? path : "#{path}/"
    end

    # Subclasses implement these.
    def default_version_path
      raise NotImplementedError
    end

    def versioned_path_pattern
      raise NotImplementedError
    end

    def payload
      raise NotImplementedError
    end

    def broker_uri
      URI(@template.broker_url)
    end

    def callback_url
      URI.join(@base_url, "/fiware/subscription_template/#{@template.id}/notification").to_s
    end

    def registration_url
      URI.join(@base_url, "/fiware/subscription_template/#{@template.id}/registration/").to_s
    end
  end
end
