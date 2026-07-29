# Serves the instance's self-published JSON-LD context (#69, step 2) at
# GET /fiware/context.jsonld.
#
# Deliberately public: brokers dereference @context at ingestion and schema
# consumers must be able to read it without credentials, exactly like any
# published JSON-LD context on the web. It discloses only what the admin
# configured for publication (subtype names; exposed attribute terms later),
# never issue data.
class FiwareContextsController < ApplicationController
  # See SubscriptionIssuesController: the explicit declaration keeps the
  # framework-default forgery protection visible to static analysis.
  protect_from_forgery with: :exception

  skip_before_action :check_if_login_required, only: [:show]

  def show
    context = RedmineGttFiware::InstanceContext.new(base_url)
    # Contexts are fetched by brokers on every ingestion; let them cache.
    expires_in 5.minutes, public: true
    render json: context.to_h, content_type: 'application/ld+json'
  end

  private

  # The configured public host wins (same semantics as the callback URLs,
  # #101); the request host is the fallback so the document stays coherent
  # when dereferenced locally on an unconfigured instance.
  def base_url
    host = Setting.host_name.to_s.strip
    host.present? ? "#{Setting.protocol}://#{host}" : request.base_url
  end
end
