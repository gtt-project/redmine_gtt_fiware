require 'uri'
require 'rack'

# This controller handles the creation of issues from subscription templates.
class SubscriptionIssuesController < ApplicationController

  # Before actions
  before_action :find_template_and_authorize
  skip_before_action :verify_authenticity_token, only: [:create]
  accept_api_auth :create

  # Creates a new issue or updates an existing one based on the provided parameters.
  def create
    @issue = find_or_initialize_issue

    if params[:attachments]
      handle_attachments
    end

    if @issue.save
      render json: @issue.as_json(include: [:status, :tracker, :author, :assigned_to, :attachments, :journals]), status: :ok
    else
      render json: { errors: @issue.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  # Finds the subscription template and checks if the current user is authorized to create issues.
  def find_template_and_authorize
    @subscription_template = SubscriptionTemplate.find_by(id: params[:subscription_template_id])
    unless @subscription_template
      render json: { error: 'Subscription template not found' }, status: :not_found
      return
    end

    unless User.current.allowed_to?(:add_issues, @subscription_template.project)
      render json: { error: 'Not authorized to create issues' }, status: :forbidden
      return
    end
  end

  # Finds an existing issue or initializes a new one.
  def find_or_initialize_issue
    existing_issue = Issue.where(fiware_entity: params["entity"], subscription_template_id: @subscription_template.id)
                      .where("created_on >= ?", Time.now - @subscription_template.threshold_create.seconds)
                      .order(created_on: :desc)
                      .first

    if existing_issue
      handle_existing_issue(existing_issue)
      existing_issue
    else
      handle_new_issue
      @issue
    end
  end

  # Handles an existing issue by initializing a journal and updating the geometry if necessary.
  def handle_existing_issue(existing_issue)
    note = existing_issue.init_journal(User.current, params["notes"])

    if Redmine::Plugin.installed?(:redmine_gtt) && @subscription_template.project.module_enabled?('gtt') && params[:geometry]
      begin
        new_geom = RedmineGtt::Conversions.to_geom(params[:geometry].to_json)
        if new_geom != existing_issue.geom
          old_geom = existing_issue.geom
          existing_issue.geom = new_geom
          note.details.build(property: 'attr', prop_key: 'geom', old_value: old_geom, value: new_geom)
        end
      rescue => e
        logger.warn "Failed to convert geometry data: #{e.message}"
      end
    end
  end

  # Handles a new issue by initializing it with the provided parameters and the subscription template.
  def handle_new_issue
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
    @issue.fiware_entity = params["entity"]
    @issue.subscription_template_id = @subscription_template.id

    if Redmine::Plugin.installed?(:redmine_gtt) && @subscription_template.project.module_enabled?('gtt') && params[:geometry]
      begin
        @issue.geom = RedmineGtt::Conversions.to_geom(params[:geometry].to_json)
      rescue => e
        logger.warn "Failed to convert geometry data: #{e.message}"
      end
    end
  end

  # Handles attachments by downloading them and attaching them to the issue.
  # Downloads go through AttachmentFetcher, which enforces the SSRF
  # protections: https only, host allowlist, public addresses only, no
  # redirects, timeouts, content-type allowlist and a size limit. The
  # stored content type is the one the server responded with; a type
  # claimed in the notification payload is not trusted. Rejected
  # attachments are skipped and logged so one bad attachment does not
  # fail the whole notification.
  def handle_attachments
    fetcher = RedmineGttFiware::AttachmentFetcher.for_template(@subscription_template)
    existing_filenames = @issue.attachments.map { |a| a.filename }

    params[:attachments].each do |attachment|
      begin
        filename = attachment['filename'].presence ||
                   File.basename(URI.parse(attachment['url'].to_s).path.to_s)

        next if filename.empty? || existing_filenames.include?(filename)

        result = fetcher.fetch(attachment['url'])
        description = attachment['description'] || ''
        uploaded_file = Rack::Multipart::UploadedFile.new(
          result.tempfile.path, result.content_type, true, filename: filename
        )
        @issue.attachments.build(file: uploaded_file, description: description, author: User.current)
      rescue RedmineGttFiware::AttachmentFetcher::RejectedError => e
        logger.warn "Rejected attachment download from #{attachment['url'].inspect}: #{e.message}"
      rescue => e
        logger.warn "Failed to attach file: #{e.message}"
      end
    end
  end
end
