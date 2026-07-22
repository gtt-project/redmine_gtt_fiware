require 'json'

# Receives broker notifications and turns their entities into Redmine issues.
#
# Since #64 the broker does pub/sub only: it POSTs the raw NGSIv2/NGSI-LD
# notification (entities under `data`) and this controller runs each entity
# through NotificationProcessor, which applies the template's field mapping and
# the create-vs-update dedup rule. All templating happens plugin-side.
class SubscriptionIssuesController < ApplicationController

  # The notification endpoint is a machine callback authenticated solely by the
  # template's webhook secret (see #58), not by a Redmine session or API key.
  # Skip the CSRF token check and the global login requirement, then
  # authenticate on the secret and act as the template's configured member.
  skip_before_action :verify_authenticity_token, only: [:create]
  skip_before_action :check_if_login_required, only: [:create]
  before_action :authenticate_webhook, only: [:create]

  WEBHOOK_SECRET_HEADER = 'X-Gtt-Webhook-Secret'.freeze

  # Processes every entity in the notification. Returns 200 with a summary when
  # at least one issue was persisted, and 422 only when the whole batch failed
  # validation (a permanent error the broker should not retry).
  def create
    entities = notification_entities
    if entities.empty?
      render json: { error: 'No entities in notification' }, status: :unprocessable_entity
      return
    end

    processor = RedmineGttFiware::NotificationProcessor.new(@subscription_template)
    results = entities.map { |entity| processor.process(entity) }
    saved = results.select(&:saved?)

    if saved.empty?
      render json: {
        processed: results.size,
        errors: results.flat_map { |r| r.issue.errors.full_messages }.uniq
      }, status: :unprocessable_entity
    else
      render json: {
        processed: results.size,
        created: saved.count(&:created?),
        updated: saved.count { |r| !r.created? },
        issues: saved.map { |r| r.issue.as_json(only: [:id, :subject, :fiware_entity]) }
      }, status: :ok
    end
  end

  private

  # Parses the broker notification body and returns the entity hashes to
  # process. Reads the raw JSON body directly (not filtered params) so
  # arbitrary entity attribute names survive untouched. Accepts the NGSIv2
  # notification shape `{ "data": [ {entity}, ... ] }`, a bare entity array, or
  # a single entity object; anything else yields an empty list.
  def notification_entities
    body = JSON.parse(request.raw_post)

    entities =
      if body.is_a?(Hash) && body['data'].is_a?(Array)
        body['data']
      elsif body.is_a?(Array)
        body
      elsif body.is_a?(Hash) && body['id'].present?
        [body]
      else
        []
      end

    entities.select { |entity| entity.is_a?(Hash) }
  rescue JSON::ParserError
    []
  end

  # Authenticates the notification on the template's webhook secret, then acts
  # as the template's configured member for the rest of the request.
  #
  # A missing template and a wrong/absent secret both return an identical 401
  # so the endpoint never reveals whether a given template id exists. The
  # secret is compared in constant time (SubscriptionTemplate#valid_webhook_secret?).
  def authenticate_webhook
    @subscription_template = SubscriptionTemplate.find_by(id: params[:subscription_template_id])
    provided_secret = request.headers[WEBHOOK_SECRET_HEADER].to_s

    unless @subscription_template && @subscription_template.valid_webhook_secret?(provided_secret)
      render json: { error: 'Unauthorized' }, status: :unauthorized
      return
    end

    # Act as the configured member. The issue is authored by this user and all
    # downstream permission checks (visibility, custom fields) use it. The
    # member or its user may have been removed since the template was created,
    # so guard against a nil user instead of raising a 500.
    member_user = @subscription_template.member&.user
    unless member_user
      render json: { error: 'Not authorized to create issues' }, status: :forbidden
      return
    end
    User.current = member_user

    unless User.current.allowed_to?(:add_issues, @subscription_template.project)
      render json: { error: 'Not authorized to create issues' }, status: :forbidden
      return
    end
  end
end
