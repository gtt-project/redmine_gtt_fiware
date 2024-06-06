require 'net/http'

class SubscriptionTemplatesController < ApplicationController
  layout 'base'

  before_action :find_project_by_project_id, except: [:index, :set_subscription_id]
  before_action :get_issue_statuses, only: [:new, :create, :edit, :update]
  before_action :get_issue_priorities, only: [:new, :create, :edit, :update]
  before_action :get_issue_categories, only: [:new, :create, :edit, :update]
  before_action :find_subscription_template, only: [:edit, :update, :destroy, :copy, :publish, :unpublish, :update_subscription_id]
  before_action :check_fiware_broker_auth_token, only: [:publish, :unpublish]

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
    prepare_payload
    if Setting.plugin_redmine_gtt_fiware['connect_via_proxy']
       if handle_fiware_action('publish')
        @subscription_templates = subscription_template_scope
        respond_to do |format|
          format.html {
            response.headers['X-Redmine-Message'] = l(:subscription_published)
            render partial: 'subscription_templates/subscription_template', collection: @subscription_templates, as: :subscription_template
          }
        end
      else
        @subscription_templates = subscription_template_scope
        respond_to do |format|
          format.html {
            response.headers['X-Redmine-Message'] = @error_message
            render partial: 'subscription_templates/subscription_template', collection: @subscription_templates, as: :subscription_template
          }
        end
      end
    else
      respond_to do |format|
        format.js # This will render `publish.js.erb`
      end
    end
  end

  def unpublish
    @broker_url = URI.join(@subscription_template.broker_url, "/v2/subscriptions/", @subscription_template.subscription_id).to_s
    if Setting.plugin_redmine_gtt_fiware['connect_via_proxy']
      if handle_fiware_action('unpublish')
        @subscription_templates = subscription_template_scope
        respond_to do |format|
          format.html {
            response.headers['X-Redmine-Message'] = l(:subscription_unpublished)
            render partial: 'subscription_templates/subscription_template', collection: @subscription_templates, as: :subscription_template
          }
        end
      else
        @subscription_templates = subscription_template_scope
        respond_to do |format|
          format.html {
            response.headers['X-Redmine-Message'] = @error_message
            render partial: 'subscription_templates/subscription_template', collection: @subscription_templates, as: :subscription_template
          }
        end
      end
    else
      respond_to do |format|
        format.js # This will render `unpublish.js.erb`
      end
    end
  end

  private

  def prepare_payload
    @broker_url = URI.join(@subscription_template.broker_url, "/v2/subscriptions").to_s
    @entity_url = URI.join(@subscription_template.broker_url, "/v2/entities").to_s
    @member = Member.find(@subscription_template.member_id)

    http_custom = {
      url: URI.join(request.base_url, "/fiware/subscription_template/#{@subscription_template.id}/notification").to_s,
      headers: {
        "Content-Type" => "application/json",
        "X-Redmine-API-Key" => User.find(@member.user_id).api_key,
        "X-Redmine-GTT-Subscription-Template-URL" => URI.join(request.base_url, "/fiware/subscription_template/#{@subscription_template.id}/registration/").to_s
      },
      method: "POST",
      json: {
        entity: "#{@entity_url}/${id}?type=${type}",
        subject: @subscription_template.subject,
        description: @subscription_template.description,
        attachments: @subscription_template.attachments,
        notes: @subscription_template.notes,
        geometry: @subscription_template.geometry
      }
    }

    @json_payload = {
      description: CGI.escape(@subscription_template.name),
      subject: {
        entities: @subscription_template.entities,
        condition: {
          notifyOnMetadataChange: @subscription_template.notify_on_metadata_change
        }
      },
      notification: {
        attrsFormat: "normalized",
        metadata: ["dateCreated", "*"],
        onlyChangedAttrs: false,
        covered: false,
        httpCustom: http_custom
      },
      throttling: Setting.plugin_redmine_gtt_fiware['fiware_broker_subscription_throttling'].to_i || 1,
      status: @subscription_template.status
    }

    @json_payload[:id] = @subscription_template.subscription_id if @subscription_template.subscription_id.present?
    @json_payload[:expires] = @subscription_template.expires if @subscription_template.expires.present?

    expression = {}

    if @subscription_template.expression_georel.present? && @subscription_template.expression_geometry.present? && @subscription_template.expression_coords.present?
      expression[:georel] = @subscription_template.expression_georel
      expression[:geometry] = @subscription_template.expression_geometry
      expression[:coords] = @subscription_template.expression_coords
    end

    expression[:q] = @subscription_template.expression_query if @subscription_template.expression_query.present?

    @json_payload[:subject][:condition][:expression] = expression if expression.present?
    @json_payload[:subject][:condition][:attrs] = JSON.parse(@subscription_template.attrs) if @subscription_template.attrs.present?
    @json_payload[:subject][:condition][:alterationTypes] = @subscription_template.alteration_types if @subscription_template.alteration_types.present?

    @json_payload = JSON.generate(@json_payload)
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
    params.require(:subscription_template).permit(:standard, :broker_url, :fiware_service, :fiware_servicepath, :subscription_id, :name, :expires, :status, :context, :entities_string, :attrs, :expression_query, :expression_georel, :expression_geometry, :expression_coords, :notify_on_metadata_change, :subject, :description, :attachments_string, :is_private, :project_id, :tracker_id, :version_id, :issue_status_id, :issue_category_id, :issue_priority_id, :member_id, :comment, :threshold_create, :threshold_create_hours, :notes, :geometry, :geometry_string, alteration_types: [])
  end

  def check_fiware_broker_auth_token
    @fiware_broker_auth_token = request.headers['HTTP_FIWARE_BROKER_AUTH_TOKEN']
  end

  def handle_fiware_action(action)

    if @fiware_broker_auth_token.blank?
      Rails.logger.error "FIWARE Broker Auth Token is missing"
      @error_message = l(:subscription_unauthorized_error)
      return false
    end

    uri = URI(@broker_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')

    request = case action
              when 'publish'
                Net::HTTP::Post.new(uri.path, initheader = {
                  'Content-Type' => 'application/json',
                  'Authorization' => "Bearer #{@fiware_broker_auth_token}"
                }).tap { |req| req.body = @json_payload }
              when 'unpublish'
                Net::HTTP::Delete.new(uri.path, initheader = {
                  'Authorization' => "Bearer #{@fiware_broker_auth_token}"
                })
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
