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

  def create_issue
    # Get the project
    @project = Project.find(params[:project_id])

    # Check if the user has the necessary permissions to create an issue in the project
    unless User.current.allowed_to?(:add_issues, @project)
      render json: { error: 'You do not have permission to create issues in this project' }, status: :forbidden
      return
    end

    # Get the notification template
    @notification_template = @project.subscription_templates.find(params[:id])

    # Create a new issue with the notification template
    @issue = @project.issues.create(issue_params)

    # Respond with the new issue
    respond_to do |format|
      if @issue.save
        format.json { render json: @issue, status: :created }
      else
        format.json { render json: @issue.errors, status: :unprocessable_entity }
      end
    end
  end

  def copy_command
    @subscription_template = SubscriptionTemplate.find(params[:id])
    @broker_url = URI::join(@subscription_template.broker_url, "/v2/notifications").to_s
    @member = Member.find(@subscription_template.member_id)

    # Construct JSON payload
    @json_payload = {
      description: @subscription_template.name,
      subject: {
        entities: @subscription_template.entities,
        condition: @subscription_template.condition
      },
      notification: {
        httpCustom: {
          url: URI::join(request.base_url, "/projects/#{@subscription_template.project_id}/fiware/notification").to_s,
          headers: {
            "Content-Type": "text/plain",
            "X-Redmine-API-Key": User.find(@member.user_id).api_key
          },
          method: "POST",
          qs: {
            subscription_template_id: @subscription_template.id,
            subject: @subscription_template.subject.to_s,
            private: @subscription_template.is_private
          },
          payload: CGI::escape(@subscription_template.description.to_s)
        }
      },
      "expires": @subscription_template.expires.present? ? @subscription_template.expires : "",
      "throttling": Setting.plugin_redmine_gtt_fiware['fiware_broker_subscription_throttling'].to_i || 1,
      "status": @subscription_template.status ? "active" : "inactive"
    }.to_json

    respond_to do |format|
      format.js # This will render `copy_command.js.erb`
    end
  end

  private

  def new_path
    new_project_subscription_template_path(@project)
  end

  def index_path
    settings_project_path(@project, tab: 'subscription_templates')
  end

  def subscription_template_params
    params.require(:subscription_template).permit(:name, :broker_url, :expires, :status, :entities_string, :condition_string, :subject, :description, :issue_status_id, :tracker_id, :member_id, :is_private)
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
