class SubscriptionTemplatesController < ApplicationController
  layout 'base'

  before_action :find_project_by_project_id
  before_action :get_issue_statuses, except: [:index, :destroy]
  before_action :authorize

  menu_item :settings, only: [:new, :create, :edit, :update, :destroy]
  helper_method :index_path

  def index
    @subscription_templates = subscription_template_scope
  end

  def edit
    @subscription_template = find_subscription_template
    @trackers = @project.trackers
    @members = @project.members
  end

  def new
    @subscription_template = SubscriptionTemplate.new
    @trackers = @project.trackers
    @members = @project.members
  end

  def create
    r = RedmineGttFiware::SaveSubscriptionTemplate.(subscription_template_params, project: @project)
    if r.subscription_template_saved?
      redirect_to params[:continue] ? new_path : index_path
    else
      @subscription_template = r.subscription_template
      @trackers = @project.trackers
      @members = @project.members
      render 'new'
    end
  end

  def update
    @subscription_template = find_subscription_template
    @trackers = @project.trackers
    @members = @project.members

    r = RedmineGttFiware::SaveSubscriptionTemplate.(subscription_template_params, subscription_template: @subscription_template)
    if r.subscription_template_saved?
      redirect_to index_path
    else
      render 'edit'
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
    prepare_payload

    respond_to do |format|
      format.js # This will render `publish.js.erb`
    end
  end

  private

  def prepare_payload
    @subscription_template = SubscriptionTemplate.find(params[:id])
    @broker_url = URI.join(@subscription_template.broker_url, "/v2/subscriptions").to_s
    @member = Member.find(@subscription_template.member_id)

    @json_payload = {
      id: @subscription_template.subscription_id.presence || "",
      description: CGI::escape(@subscription_template.name),
      subject: {
        entities: @subscription_template.entities,
        condition: @subscription_template.condition
      },
      notification: {
        httpCustom: {
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
      },
      expires: @subscription_template.expires.presence || "",
      throttling: Setting.plugin_redmine_gtt_fiware['fiware_broker_subscription_throttling'].to_i || 1,
      status: @subscription_template.status ? "active" : "inactive"
    }

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
    params.require(:subscription_template).permit(:name, :broker_url, :expires, :status, :entities_string, :condition_string, :subject, :description, :issue_status_id, :tracker_id, :member_id, :is_private, :subscription_id)
  end

  def issue_params
    # Defines the allowed parameters for an issue
    params.require(:issue).permit(:subscription_template_id, :subject, :description, :is_private)
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

end
