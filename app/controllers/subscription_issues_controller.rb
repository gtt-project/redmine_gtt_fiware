class SubscriptionIssuesController < ApplicationController

  before_action :find_template_and_authorize
  skip_before_action :verify_authenticity_token, only: [:create]
  accept_api_auth :create

  def create
    # Create a new issue based on the provided parameters and the subscription template
    @issue = Issue.new()
    @issue.project = @subscription_template.project
    @issue.tracker = @subscription_template.tracker
    @issue.subject = params[:subject]
    @issue.description = params[:description]
    @issue.is_private = @subscription_template.is_private
    @issue.status = @subscription_template.issue_status
    @issue.author = User.current
    @issue.category = @subscription_template.issue_category
    @issue.priority = @subscription_template.issue_priority
    @issue.fixed_version = @subscription_template.version

    logger.info "################################################################################"
    logger.info "################################################################################"
    logger.info "Request received to create a new issue based on a subscription template"
    logger.info "Request parameters: #{params}"
    logger.info "################################################################################"

    # If the redmine_gtt plugin is installed and enabled, and geometry data is provided,
    # try to convert it to an RGeo geometry object
    if Redmine::Plugin.installed?(:redmine_gtt) && @subscription_template.project.module_enabled?('gtt') && params[:geometry]
      begin
        @issue.geom = RedmineGtt::Conversions.to_geom(params[:geometry].to_json)
      rescue => e
        logger.warn "Failed to convert geometry data: #{e.message}"
      end
    end

    logger.info "################################################################################"
    logger.info "Create issue key/value:"
    @issue.attributes.each do |key, value|
      logger.info "#{key}: #{value}"
    end
    logger.info "################################################################################"
    logger.info "Subscription template key/value pairs:"
    @subscription_template.attributes.each do |key, value|
      logger.info "#{key}: #{value}"
    end
    logger.info "################################################################################"
    logger.info "################################################################################"

    if @issue.save
      # Respond with the newly created issue and a 201 status code
      render json: @issue.as_json(include: [:status, :tracker, :author, :assigned_to]), status: :created
    else
      # If saving fails, respond with error messages and a 422 status code
      render json: { errors: @issue.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def find_template_and_authorize
    # Get subscription template from the provided ID
    @subscription_template = SubscriptionTemplate.find_by(id: params[:subscription_template_id])
    unless @subscription_template
      render json: { error: 'Subscription template not found' }, status: :not_found
      return
    end

    # Check if the user has permissions to add issues to the project
    unless User.current.allowed_to?(:add_issues, @subscription_template.project)
      render json: { error: 'Not authorized to create issues' }, status: :forbidden
      return
    end
  end

  def issue_params
    # Defines the allowed parameters for an issue
    params.require(:issue).permit(:project, :tracker, :subject, :description, :is_private, :status, :author, :fixed_version, :category, :priority)
  end

end
