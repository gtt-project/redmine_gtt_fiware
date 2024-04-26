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
