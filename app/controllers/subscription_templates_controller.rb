require 'net/http'
require 'uri'

class SubscriptionTemplatesController < ApplicationController
  layout 'base'

  before_action :find_project_by_project_id, except: [:index, :set_subscription_id]
  before_action :get_issue_statuses, only: [:new, :create, :edit, :update]
  before_action :get_issue_priorities, only: [:new, :create, :edit, :update]
  before_action :get_issue_categories, only: [:new, :create, :edit, :update]
  before_action :find_subscription_template, only: [:edit, :update, :destroy, :copy, :publish, :unpublish, :sync, :update_subscription_id]
  before_action :check_fiware_broker_auth_token, only: [:publish, :unpublish, :sync]

  # set_subscription_id is the broker/tooling registration callback, a JSON API
  # endpoint authenticated by API key. accept_api_auth enables key auth, and
  # Redmine skips the CSRF token check for api_request? (json/xml) requests, so
  # no manual verify_authenticity_token skip is needed. The state-changing
  # browser actions (publish/unpublish) keep full CSRF protection via the
  # rails-ujs token.
  accept_api_auth :set_subscription_id
  before_action :authorize, except: [:set_subscription_id]

  helper_method :index_path

  def index
    @subscription_templates = subscription_template_scope
  end

  def new
    @subscription_template = SubscriptionTemplate.new
  end

  def edit; end

  def create
    r = RedmineGttFiware::SaveSubscriptionTemplate.(subscription_template_params, project: @project)
    if r.subscription_template_saved?
      redirect_to params[:continue] ? new_path : index_path
    else
      @subscription_template = r.subscription_template
      render 'new'
    end
  end

  def update
    r = RedmineGttFiware::SaveSubscriptionTemplate.(subscription_template_params, subscription_template: @subscription_template)
    if r.subscription_template_saved?
      redirect_to index_path
    else
      render 'edit'
    end
  end

  def update_subscription_id
    @subscription_template = find_subscription_template
    @subscription_template.update(subscription_id: params[:subscription_id])

    @subscription_templates = subscription_template_scope
    respond_to do |format|
      format.js { render partial: 'subscription_templates/subscription_template', collection: @subscription_templates, as: :subscription_template }
    end
  end

  def set_subscription_id
    unless User.current.logged?
      render json: { error: 'API key is missing or invalid' }, status: :unauthorized
      return
    end

    @subscription_template = SubscriptionTemplate.find(params[:subscription_template_id])

    unless User.current.allowed_to?(:manage_subscription_templates, @subscription_template.project)
      render json: { error: 'You do not have permission to manage subscription templates' }, status: :forbidden
      return
    end

    @subscription_template.update(subscription_id: params[:subscription_id])

    render json: { message: 'Subscription ID updated successfully' }, status: :ok
  end

  def destroy
    @subscription_template.destroy
    redirect_to index_path
  end

  def copy
    prepare_payload

    respond_to do |format|
      format.js # This will render `copy.js.erb`
    end
  end

  def publish
    # Ensure the template has a webhook secret (backfills a blank one); the
    # secret is stable for the life of the template so the broker and plugin
    # never disagree on it. prepare_payload (below) embeds it.
    @subscription_template.ensure_webhook_secret!
    handle_publish_unpublish('publish', l(:subscription_published), 'publish')
  end

  def unpublish
    @subscription_request = subscription_request
    @broker_url = @subscription_request.subscription_url
    handle_publish_unpublish('unpublish', l(:subscription_unpublished), 'unpublish')
  end

  # Reconciles local state with the broker (#13). Always runs server-side:
  # 404 from the broker clears the stored subscription id (the subscription is
  # gone, e.g. a oneshot fired or it expired and was purged); 200 updates the
  # local status from the broker's. The auth token comes from the stored
  # connection or, in browser/proxy mode, the request header.
  def sync
    @subscription_request = subscription_request
    @sync_message =
      if @subscription_template.subscription_id.blank?
        l(:subscription_sync_no_subscription)
      else
        perform_sync
      end

    @subscription_templates = subscription_template_scope
    respond_to do |format|
      format.js { render 'sync' }
    end
  end

  private

  # js_template is the template basename (e.g. 'publish'); Rails resolves it
  # to <name>.js.erb for the js format. Passing the full 'publish.js.erb'
  # filename here makes Rails look for publish.js.erb.js and 404.
  def handle_publish_unpublish(action, success_message, js_template)
    prepare_payload if action == 'publish'

    if server_side_broker_call?
      if handle_fiware_action(action)
        render_subscription_templates(success_message)
      else
        render_subscription_templates(@error_message)
      end
    else
      respond_to do |format|
        format.js { render js_template }
      end
    end
  end

  # Queries the broker for the template's subscription and reconciles local
  # state. Returns the user-facing message. A 200 whose status the plugin
  # cannot interpret is reported as an error, not a successful sync.
  def perform_sync
    response = fetch_remote_subscription
    case response
    when Net::HTTPNotFound
      @subscription_template.update(subscription_id: nil)
      l(:subscription_sync_removed)
    when Net::HTTPSuccess
      if apply_remote_status(JSON.parse(response.body))
        l(:subscription_synced)
      else
        Rails.logger.error 'FIWARE broker sync: unrecognized subscription status in response'
        l(:subscription_sync_error)
      end
    else
      Rails.logger.error "FIWARE broker sync failed: #{response.code} #{response.message}"
      l(:subscription_sync_error)
    end
  rescue JSON::ParserError
    Rails.logger.error 'FIWARE broker sync returned an unparsable body'
    l(:subscription_sync_error)
  rescue StandardError => e
    Rails.logger.error "Error syncing subscription: #{e.message}"
    l(:subscription_sync_error)
  end

  def fetch_remote_subscription
    uri = URI(@subscription_request.subscription_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')

    headers = {}
    headers['Authorization'] = "Bearer #{@fiware_broker_auth_token}" if @fiware_broker_auth_token.present?
    headers.merge!(@subscription_request.tenant_headers)
    # request_uri keeps any query string and never yields an empty path.
    http.request(Net::HTTP::Get.new(uri.request_uri, headers))
  end

  # Maps the broker's reported subscription state onto the local status.
  # NGSIv2 reports status active/inactive/oneshot/expired/failed ('failed'
  # means the last notification failed but the subscription is still active);
  # NGSI-LD reports status active/paused/expired plus isActive. Returns the
  # recognized status, or nil when the response carries none the plugin
  # understands (the caller reports that as an error).
  def apply_remote_status(subscription)
    remote = subscription['status'].to_s
    if remote.empty? && @subscription_template.ngsi_ld? && subscription.key?('isActive')
      remote = subscription['isActive'] == false ? 'paused' : 'active'
    end

    normalized =
      case remote
      when 'active', 'inactive', 'oneshot' then remote
      when 'failed' then 'active'
      when 'paused', 'expired' then 'inactive'
      end
    return nil if normalized.nil?

    @subscription_template.update(status: normalized) unless normalized == @subscription_template.status
    normalized
  end

  # The broker call runs server-side when the proxy setting is on OR the
  # template's connection stores its token (#67): a stored token must never
  # reach the browser.
  def server_side_broker_call?
    Setting.plugin_redmine_gtt_fiware['connect_via_proxy'] ||
      @subscription_template.broker_connection&.stored_auth?
  end

  def render_subscription_templates(message)
    @subscription_templates = subscription_template_scope
    respond_to do |format|
      format.html {
        response.headers['X-Redmine-Message'] = message
        render partial: 'subscription_templates/subscription_template', collection: @subscription_templates, as: :subscription_template
      }
    end
  end

  # Builds the broker request via SubscriptionRequest, which picks the NGSIv2 or
  # NGSI-LD payload shape from the template's standard (#63). The broker is
  # pub/sub only (#64): the notification block carries just the callback URL and
  # auth headers; all field mapping happens plugin-side in NotificationProcessor.
  def prepare_payload
    @subscription_request = subscription_request
    @broker_url = @subscription_request.subscriptions_url
    @entity_url = @subscription_request.entities_url
    @json_payload = @subscription_request.to_json
  end

  def subscription_request
    RedmineGttFiware::SubscriptionRequest.build(
      @subscription_template,
      base_url: request.base_url,
      throttling: Setting.plugin_redmine_gtt_fiware['fiware_broker_subscription_throttling'].to_i
    )
  end

  def new_path
    new_project_subscription_template_path(@project)
  end

  def index_path
    settings_project_path(@project, tab: 'subscription_templates')
  end

  def find_subscription_template
    @subscription_template = subscription_template_scope.find(params[:id])
  end

  def find_project_by_project_id
    @project = Project.find(params[:project_id])
  end

  def subscription_template_scope
    SubscriptionTemplate.where(project_id: @project.id).order(name: :asc)
  end

  def get_issue_statuses
    @issue_statuses = IssueStatus.all.sorted
  end

  def get_issue_categories
    @issue_categories = IssueCategory.all
  end

  def get_issue_priorities
    @issue_priorities = IssuePriority.all.sorted
  end

  def subscription_template_params
    params[:subscription_template][:alteration_types] ||= []
    params.require(:subscription_template).permit(:broker_connection_id, :subscription_id, :name, :expires, :status, :context, :entities_string, :attrs, :expression_query, :expression_georel, :expression_geometry, :expression_coords, :notify_on_metadata_change, :subject, :description, :attachments_string, :is_private, :project_id, :tracker_id, :version_id, :issue_status_id, :issue_category_id, :issue_priority_id, :member_id, :comment, :threshold_create, :threshold_create_hours, :notes, :geometry, :geometry_string, alteration_types: [])
  end

  # Stored connections supply their encrypted token server-side; browser-mode
  # connections keep the pre-#67 behaviour of a per-request header token.
  def check_fiware_broker_auth_token
    connection = @subscription_template&.broker_connection
    @fiware_broker_auth_token =
      if connection&.stored_auth?
        connection.auth_token
      else
        request.headers['HTTP_FIWARE_BROKER_AUTH_TOKEN']
      end
  end

  def handle_fiware_action(action)
    # A stored connection may legitimately have no token (an open broker); in
    # browser/proxy mode a missing header token is an error, as before.
    if @fiware_broker_auth_token.blank? && !@subscription_template.broker_connection&.stored_auth?
      Rails.logger.error "FIWARE Broker Auth Token is missing"
      @error_message = l(:subscription_unauthorized_error)
      return false
    end

    uri = URI(@broker_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')

    headers = {}
    headers['Authorization'] = "Bearer #{@fiware_broker_auth_token}" if @fiware_broker_auth_token.present?
    headers['Content-Type'] = @subscription_request.content_type if action == 'publish'
    headers.merge!(@subscription_request.tenant_headers)

    request = case action
              when 'publish'
                Net::HTTP::Post.new(uri.path, headers).tap { |req| req.body = @json_payload }
              when 'unpublish'
                Net::HTTP::Delete.new(uri.path, headers)
              else
                Rails.logger.error "Unknown action: #{action}"
                @error_message = l(:general_action_error)
                return false
              end

    response = http.request(request)

    Rails.logger.info "FIWARE Broker Response Code: #{response.code}"
    Rails.logger.info "FIWARE Broker Response Message: #{response.message}"

    if response.code.to_i == 201 && action == 'publish'
      location_header = response['location'] || response['Location']
      if location_header
        subscription_id = location_header.split('/').last
        @subscription_template.update(subscription_id: subscription_id)
        return true
      else
        Rails.logger.error "Location header is missing in the response"
        @error_message = l(:general_action_error)
        return false
      end
    elsif response.code.to_i == 204 && action == 'unpublish'
      @subscription_template.update(subscription_id: nil)
      return true
    end

    if response.code.to_i >= 400
      Rails.logger.error "FIWARE Broker error: #{response.body}"
      @error_message = l(:general_action_error)
      false
    else
      true
    end
  rescue StandardError => e
    Rails.logger.error "Error handling FIWARE action: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    @error_message = l(:general_action_error)
    false
  end

end
