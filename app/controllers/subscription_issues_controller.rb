class SubscriptionIssuesController < ApplicationController

  before_action :find_template_and_authorize
  skip_before_action :verify_authenticity_token, only: [:create]
  accept_api_auth :create

  def create
    # Check if there's an existing issue with the same fiware_entity and subscription_template_id
    # that was created within the threshold_create time frame
    existing_issue = Issue.where(fiware_entity: params["entity"], subscription_template_id: @subscription_template.id)
                      .where("created_on >= ?", Time.now - @subscription_template.threshold_create.seconds)
                      .order(created_on: :desc)
                      .first

    if existing_issue
      # Create a new journal note for the existing issue
      note = existing_issue.init_journal(User.current, params["notes"])

      # If the redmine_gtt plugin is installed and enabled, and geometry data is provided,
      # try to convert it to an RGeo geometry object and update the issue's geometry
      if Redmine::Plugin.installed?(:redmine_gtt) && @subscription_template.project.module_enabled?('gtt') && params[:geometry]
        begin
          new_geom = RedmineGtt::Conversions.to_geom(params[:geometry].to_json)
          if new_geom != existing_issue.geom
            old_geom = existing_issue.geom
            existing_issue.geom = new_geom
            # Create a new JournalDetail record to track the change to the geom attribute
            note.details.build(property: 'attr', prop_key: 'geom', old_value: old_geom, value: new_geom)
          end
        rescue => e
          logger.warn "Failed to convert geometry data: #{e.message}"
        end
      end

      # Save the existing issue and respond with the appropriate JSON response
      if existing_issue.save
        render json: existing_issue.as_json(include: [:status, :tracker, :author, :assigned_to, :journals]), status: :ok
      else
        render json: { errors: existing_issue.errors.full_messages }, status: :unprocessable_entity
      end
    else
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

      # Set the fiware_entity and subscription_template_id attributes of the new issue
      @issue.fiware_entity = params["entity"]
      @issue.subscription_template_id = @subscription_template.id

      # If the redmine_gtt plugin is installed and enabled, and geometry data is provided,
      # try to convert it to an RGeo geometry object
      if Redmine::Plugin.installed?(:redmine_gtt) && @subscription_template.project.module_enabled?('gtt') && params[:geometry]
        begin
          @issue.geom = RedmineGtt::Conversions.to_geom(params[:geometry].to_json)
        rescue => e
          logger.warn "Failed to convert geometry data: #{e.message}"
        end
      end

      if @issue.save
        # Respond with the newly created issue and a 201 status code
        render json: @issue.as_json(include: [:status, :tracker, :author, :assigned_to]), status: :created
      else
        # If saving fails, respond with error messages and a 422 status code
        render json: { errors: @issue.errors.full_messages }, status: :unprocessable_entity
      end
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
