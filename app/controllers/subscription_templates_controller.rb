require 'net/http'
require 'uri'

class SubscriptionTemplatesController < ApplicationController
  layout 'base'

  # See SubscriptionIssuesController: the explicit declaration keeps the
  # framework-default forgery protection visible to static analysis.
  protect_from_forgery with: :exception

  # index is nested under a project since #22 (the REST API), so it needs the
  # project too; only the broker's registration callback is project-less.
  before_action :find_project_by_project_id, except: [:set_subscription_id]
  before_action :load_form_collections, only: [:new, :create, :edit, :update]
  before_action :find_subscription_template, only: [:edit, :update, :destroy, :copy, :publish, :unpublish, :sync, :update_subscription_id]
  before_action :check_fiware_broker_auth_token, only: [:publish, :unpublish, :sync]

  # set_subscription_id is the broker/tooling registration callback, a JSON API
  # endpoint authenticated by API key. accept_api_auth enables key auth, and
  # Redmine skips the CSRF token check for api_request? (json/xml) requests, so
  # no manual verify_authenticity_token skip is needed. The state-changing
  # browser actions (publish/unpublish) keep full CSRF protection via the
  # rails-ujs token.
  accept_api_auth :set_subscription_id, :index, :show, :create, :update, :destroy
  before_action :authorize, except: [:set_subscription_id]

  helper_method :index_path, :form_issue_statuses

  def index
    respond_to do |format|
      # The HTML surface for the list is the project's FIWARE tab.
      format.html { redirect_to index_path }
      format.api do
        scope = subscription_template_scope
        @subscription_template_count = scope.count
        @offset, @limit = api_offset_and_limit
        @subscription_templates = scope.offset(@offset).limit(@limit).to_a
      end
    end
  end

  def show
    @subscription_template = subscription_template_scope.find(params[:id])
    respond_to do |format|
      format.html { redirect_to edit_project_subscription_template_path(@project, @subscription_template) }
      format.api
    end
  end

  # Prefilled defaults keep the happy path publishable without opening any
  # advanced section (#66): a generic subject/description template and the
  # current user's membership as the issue author.
  def new
    @subscription_template = SubscriptionTemplate.new(
      subject: l(:text_subscription_template_default_subject),
      description: l(:text_subscription_template_default_description)
    )
    @subscription_template.member = @project.members.detect { |m| m.user_id == User.current.id }
  end

  def edit; end

  # The statuses a new issue can take for a tracker/member pair (#103): the
  # same workflow data the regular issue form uses. Fetched by the form when
  # the tracker or the "Sent from user" member changes.
  def allowed_statuses
    tracker = @project.trackers.find_by(id: params[:tracker_id])
    member = @project.members.find_by(id: params[:member_id])
    statuses = allowed_issue_statuses(tracker: tracker, member: member)
    render json: statuses.map { |s| { id: s.id, name: s.name } }
  end

  def create
    r = RedmineGttFiware::SaveSubscriptionTemplate.(subscription_template_params, project: @project)
    @subscription_template = r.subscription_template
    if r.subscription_template_saved?
      publish_after_create(@subscription_template) if params[:publish_after_create].present?
      respond_to do |format|
        format.html { redirect_to params[:continue] ? new_path : index_path }
        format.api do
          render action: 'show', status: :created,
                 location: project_subscription_template_path(@project, @subscription_template)
        end
      end
    else
      respond_to do |format|
        format.html { render 'new' }
        format.api { render_validation_errors(@subscription_template) }
      end
    end
  end

  def update
    r = RedmineGttFiware::SaveSubscriptionTemplate.(subscription_template_params, subscription_template: @subscription_template)
    if r.subscription_template_saved?
      respond_to do |format|
        format.html { redirect_to index_path }
        format.api { render_api_ok }
      end
    else
      respond_to do |format|
        format.html { render 'edit' }
        format.api { render_validation_errors(@subscription_template) }
      end
    end
  end

  def update_subscription_id
    # @subscription_template is loaded by the find_subscription_template
    # before_action. presence: browser-mode unpublish PATCHes an empty string;
    # store nil so a cleared subscription looks the same regardless of which
    # mode cleared it.
    unless @subscription_template.update(subscription_id: params[:subscription_id].presence)
      Rails.logger.error "Subscription id for template #{@subscription_template.id} could not be stored: " \
                         "#{@subscription_template.errors.full_messages.join(', ')}"
    end

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

    @subscription_template = SubscriptionTemplate.find_by(id: params[:subscription_template_id])
    if @subscription_template.nil?
      render json: { error: 'Subscription template not found' }, status: :not_found
      return
    end

    unless User.current.allowed_to?(:manage_subscription_templates, @subscription_template.project)
      render json: { error: 'You do not have permission to manage subscription templates' }, status: :forbidden
      return
    end

    if @subscription_template.update(subscription_id: params[:subscription_id])
      render json: { message: 'Subscription ID updated successfully' }, status: :ok
    else
      render json: { errors: @subscription_template.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @subscription_template.destroy
    respond_to do |format|
      format.html { redirect_to index_path }
      format.api { render_api_ok }
    end
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

  # Reconciles local state with the broker (#13). Always runs server-side;
  # the auth token comes from the stored connection or, in browser/proxy
  # mode, the request header. The reconciliation rules live in
  # RedmineGttFiware::SubscriptionSync.
  def sync
    @subscription_request = subscription_request
    message_key = RedmineGttFiware::SubscriptionSync.new(
      @subscription_template,
      subscription_request: @subscription_request,
      token: @fiware_broker_auth_token
    ).call
    @sync_message = l(message_key)

    @subscription_templates = subscription_template_scope
    respond_to do |format|
      format.js { render 'sync' }
    end
  end

  # Live preview (#68): fetches one entity of the given type from the broker
  # connection and renders the subject/description/notes templates against it
  # through the same pipeline notifications use (Entity + TemplateRenderer),
  # so what the preview shows is exactly what a notification would produce.
  def preview
    connection = BrokerConnection.find_by(id: params[:broker_connection_id])
    if connection.nil?
      render json: { error: l(:preview_no_connection) }, status: :unprocessable_entity
      return
    end

    raw_entity = fetch_sample_entity(connection, params[:entity_type].to_s.strip)
    if raw_entity.nil?
      render json: { error: @preview_error }, status: :unprocessable_entity
      return
    end

    entity = RedmineGttFiware::Entity.from(raw_entity, connection.standard)
    render json: {
      entity_id: entity.id,
      subject: RedmineGttFiware::TemplateRenderer.render(params[:subject].to_s, entity),
      description: RedmineGttFiware::TemplateRenderer.render(params[:description].to_s, entity),
      notes: params[:notes].present? ? RedmineGttFiware::TemplateRenderer.render(params[:notes], entity) : nil,
      has_geometry: entity.geometry.present?
    }
  end

  private

  # GET one entity of the type from the broker's entities endpoint. Uses the
  # connection's stored token when it has one; an open broker works without.
  # Returns nil (with @preview_error set) on any failure.
  def fetch_sample_entity(connection, entity_type)
    if entity_type.blank?
      @preview_error = l(:preview_no_entity_type)
      return nil
    end

    url = "#{connection.api_base}/entities?#{URI.encode_www_form(type: entity_type, limit: 1)}"
    response = RedmineGttFiware::BrokerHttp.request(
      :get, url,
      connection: connection,
      token: connection.stored_auth? ? connection.auth_token : nil,
      headers: { 'Accept' => 'application/json' }
    )

    unless response.is_a?(Net::HTTPSuccess)
      @preview_error = l(:preview_broker_error, code: response.code)
      return nil
    end

    entities = JSON.parse(response.body)
    entity = entities.is_a?(Array) ? entities.first : entities
    @preview_error = l(:preview_no_entity, type: entity_type) if entity.nil?
    entity
  rescue JSON::ParserError
    @preview_error = l(:preview_broker_error, code: 'JSON')
    nil
  rescue StandardError => e
    Rails.logger.error "FIWARE preview fetch failed: #{e.message}"
    @preview_error = l(:preview_broker_error, code: e.class.name)
    nil
  end

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

  # "Create and publish" (#66): after a successful create, publish the
  # subscription server-side. Only possible with a stored-token connection
  # (the browser-mode token never reaches the server); the form hides the
  # button otherwise, and this guard covers direct POSTs.
  def publish_after_create(template)
    connection = template.broker_connection
    unless connection&.stored_auth?
      flash[:error] = l(:subscription_unauthorized_error)
      return
    end

    @subscription_template = template
    @subscription_template.ensure_webhook_secret!
    @fiware_broker_auth_token = connection.auth_token
    prepare_payload
    if handle_fiware_action('publish')
      flash[:notice] = l(:subscription_published)
    else
      flash[:error] = @error_message
    end
  end

  # Whether the broker call runs on the server is now a property of the
  # connection (#95): 'stored' and 'proxied' both run server-side, 'browser'
  # calls the broker straight from the browser.
  def server_side_broker_call?
    @subscription_template.broker_connection&.server_side?
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
      base_url: callback_base_url,
      throttling: @subscription_template.effective_throttling
    )
  end

  # Base URL the broker calls back on (#101). The publishing admin's request
  # host is frequently not broker-reachable (localhost in development, an
  # internal name behind a reverse proxy), so the configured canonical host
  # wins: Setting.protocol + Setting.host_name, exactly what core uses for
  # links in notification emails (host_name may carry a sub-URI path).
  # An unconfigured host_name keeps the previous request-based behaviour.
  def callback_base_url
    host = Setting.host_name.to_s.strip
    host.present? ? "#{Setting.protocol}://#{host}" : request.base_url
  end

  def new_path
    new_project_subscription_template_path(@project)
  end

  def index_path
    settings_project_path(@project, tab: 'subscription_templates')
  end

  # find_project_by_project_id comes from core's ApplicationController,
  # including its render_404 on an unknown project.

  def find_subscription_template
    @subscription_template = subscription_template_scope.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # Preloads what the list partial and the API render per row.
  def subscription_template_scope
    SubscriptionTemplate.where(project_id: @project.id)
                        .includes(:project, :broker_connection, :tracker, :issue_status,
                                  :issue_priority, :issue_category, :version, :member)
                        .order(name: :asc)
  end

  # The status list the form renders initially (#103): workflow-allowed for
  # the template's tracker and member, falling back to the full list when the
  # pair is not known yet. Lazy (helper_method) because @subscription_template
  # is built inside the actions, after before_actions ran.
  def form_issue_statuses
    @form_issue_statuses ||= allowed_issue_statuses(
      tracker: @subscription_template&.tracker || @project.trackers.first,
      member: @subscription_template&.member,
      current_status: @subscription_template&.issue_status
    )
  end

  # Mirrors the regular issue form: a new issue authored by the member's user
  # can start at the tracker default and take the workflow's new-issue
  # transitions for the member's roles. Falls back to the full sorted list
  # when the tracker or a User principal is missing (e.g. group members), and
  # keeps a stored status in the list so an edit never silently drops it.
  def allowed_issue_statuses(tracker:, member:, current_status: nil)
    user = member&.principal
    statuses =
      if tracker && user.is_a?(User)
        issue = Issue.new(project: @project, tracker: tracker)
        issue.author = user
        allowed = issue.new_statuses_allowed_to(user, true)
        allowed.presence || IssueStatus.sorted.to_a
      else
        IssueStatus.sorted.to_a
      end
    statuses |= [current_status] if current_status
    statuses
  end

  # The form's select collections. Categories are scoped to the project:
  # they are project-local in core, and the unscoped list both leaked other
  # projects' category names and offered ids the model rejects.
  def load_form_collections
    @issue_categories = @project.issue_categories
    @issue_priorities = IssuePriority.all.sorted
  end

  def subscription_template_params
    # require first: a request without the root key must answer 400
    # (ParameterMissing), not crash on the normalization below.
    attributes = params.require(:subscription_template)
    if api_request?
      # Structured API inputs (entities/attachments/geometry/attrs) become
      # the *_string inputs the model validates.
      RedmineGttFiware::ApiStructuredInput.normalize!(attributes)
    else
      # The form omits unchecked boxes, so an absent value means "none".
      # An API client that omits the key means "leave it alone", and on
      # create the model's default applies.
      attributes[:alteration_types] ||= []
    end
    # project_id is deliberately not permitted: the project comes from the
    # route, and SaveSubscriptionTemplate assigns it before the attributes, so
    # a permitted project_id would let a request move a subscription into
    # another project (a real hole once the API can send arbitrary fields).
    # geometry is likewise only writable through geometry_string, which is
    # parsed and validated; the raw serialized column stays unassignable.
    attributes.permit(:broker_connection_id, :subscription_id, :name, :expires, :status, :federation_policy, :federation_watch, :throttling, :context, :entities_string, :attrs, :expression_query, :expression_georel, :expression_geometry, :expression_coords, :notify_on_metadata_change, :subject, :description, :attachments_string, :is_private, :tracker_id, :version_id, :issue_status_id, :issue_category_id, :issue_priority_id, :member_id, :comment, :threshold_create, :threshold_create_hours, :notes, :geometry_string, :geofence_notes, alteration_types: [], issue_custom_field_values: {})
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

    connection = @subscription_template.broker_connection
    response = case action
               when 'publish'
                 RedmineGttFiware::BrokerHttp.request(
                   :post, @broker_url, connection: connection, token: @fiware_broker_auth_token,
                   body: @json_payload, content_type: @subscription_request.content_type
                 )
               when 'unpublish'
                 RedmineGttFiware::BrokerHttp.request(
                   :delete, @broker_url, connection: connection, token: @fiware_broker_auth_token
                 )
               else
                 Rails.logger.error "Unknown action: #{action}"
                 @error_message = l(:general_action_error)
                 return false
               end

    Rails.logger.info "FIWARE Broker Response Code: #{response.code}"
    Rails.logger.info "FIWARE Broker Response Message: #{response.message}"

    if response.code.to_i == 201 && action == 'publish'
      location_header = response['location'] || response['Location']
      if location_header
        subscription_id = location_header.split('/').last
        # The subscription is live on the broker at this point; failing to
        # store its id locally must be surfaced, not silently ignored.
        unless @subscription_template.update(subscription_id: subscription_id)
          Rails.logger.error "Subscription #{subscription_id} published but could not be stored: #{@subscription_template.errors.full_messages.join(', ')}"
          @error_message = l(:general_action_error)
          return false
        end
        return true
      else
        Rails.logger.error "Location header is missing in the response"
        @error_message = l(:general_action_error)
        return false
      end
    elsif response.code.to_i == 204 && action == 'unpublish'
      # The subscription is gone on the broker either way; failing to clear
      # the local id must be surfaced, like the publish case above.
      unless @subscription_template.update(subscription_id: nil)
        Rails.logger.error "Subscription removed on the broker but the local id could not be cleared: " \
                           "#{@subscription_template.errors.full_messages.join(', ')}"
        @error_message = l(:general_action_error)
        return false
      end
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
