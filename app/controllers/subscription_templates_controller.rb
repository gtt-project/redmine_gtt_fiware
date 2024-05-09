class SubscriptionTemplatesController < ApplicationController
  layout 'base'

  before_action :find_project_by_project_id, except: [:index]
  before_action :get_issue_statuses, only: [:new, :create, :edit, :update]
  before_action :get_issue_priorities, only: [:new, :create, :edit, :update]
  before_action :get_issue_categories, only: [:new, :create, :edit, :update]
  before_action :authorize

  helper_method :index_path

  def index
    @subscription_templates = subscription_template_scope
  end

  def new
    @subscription_template = SubscriptionTemplate.new
  end

  def edit
    @subscription_template = find_subscription_template
  end

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
    @subscription_template = find_subscription_template

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

  def destroy
    @subscription_template = find_subscription_template
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

    respond_to do |format|
      format.js # This will render `publish.js.erb`
    end
  end

  def unpublish
    @subscription_template = SubscriptionTemplate.find(params[:id])
    @broker_url = URI.join(@subscription_template.broker_url, "/v2/subscriptions/", @subscription_template.subscription_id).to_s

    respond_to do |format|
      format.js # This will render `unpublish.js.erb`
    end
  end

  private

  def prepare_payload
    @subscription_template = SubscriptionTemplate.find(params[:id])
    @broker_url = URI.join(@subscription_template.broker_url, "/v2/subscriptions").to_s
    @member = Member.find(@subscription_template.member_id)

    httpCustom = {
      url: URI.join(request.base_url, "/fiware/subscription_template/#{@subscription_template.id}/notification").to_s,
      headers: {
        "Content-Type": "application/json",
        "X-Redmine-API-Key": User.find(@member.user_id).api_key
      },
      method: "POST",
      json: {
        subject: @subscription_template.subject,
        description: @subscription_template.description
      }
    }

    httpCustom[:json][:attachments] = @subscription_template.attachments if @subscription_template.attachments

    @json_payload = {
      description: CGI::escape(@subscription_template.name),
      subject: {
        entities: @subscription_template.entities,
        condition: {
          notifyOnMetadataChange: @subscription_template.notify_on_metadata_change
        }
      },
      notification: {
        httpCustom: httpCustom,
        attrsFormat: "normalized",
        metadata: ["dateCreated", "*"],
        onlyChangedAttrs: false,
        covered: false
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

    @json_payload = JSON.pretty_generate(@json_payload)
      .gsub("\\", "\\\\\\\\") # escape backslashes
      .gsub("\r", "\\r") # escape carriage return
      .gsub("\n", "\\n") # escape newline
      .gsub("\t", "\\t") # escape tab
      .gsub("\f", "\\f") # escape form feed
      .gsub("\b", "\\b") # escape backspace
      .gsub("\"", "\\\"") # escape double quotes
  end

  def new_path
    new_project_subscription_template_path(@project)
  end

  def index_path
    settings_project_path(@project, tab: 'subscription_templates')
  end

  def subscription_template_params
    params[:subscription_template][:alteration_types] ||= []
    params.require(:subscription_template).permit(:standard, :broker_url, :fiware_service, :fiware_servicepath, :subscription_id, :name, :expires, :status, :context, :entities_string, :attrs, :expression_query, :expression_georel, :expression_geometry, :expression_coords, :notify_on_metadata_change, :subject, :description, :attachments_string, :is_private, :project_id, :tracker_id, :version_id, :issue_status_id, :issue_category_id, :issue_priority_id, :member_id, :comment, alteration_types: [])
  end

  def find_subscription_template
    subscription_template_scope.find params[:id]
  end

  def find_project_by_project_id
    @project = Project.find params[:project_id]
  end

  def subscription_template_scope
    SubscriptionTemplate.order(name: :asc).where(project_id: @project.id)
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

end
