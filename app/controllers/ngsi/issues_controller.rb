# Ngsi::IssuesController handles the NGSI JSON-LD and NGSIv2 issue requests.
# It inherits from Ngsi::BaseController and provides actions
# for handling issue-related endpoints.
class Ngsi::IssuesController < Ngsi::BaseController
  before_action :find_issue, only: [:show]
  before_action :plugin_enabled?, only: [:show]

  # Processes the issue request and renders the JSON-LD or NGSIv2 representation.
  def show
    render_issue_template
  end

  private

  # Set the @issue based on the ID parameter and handle errors if the issue is not found
  # or not visible based on permissions.
  def find_issue
    issue = Issue.find_by(id: params[:id])

    if issue.nil?
      render json: { error: l(:gtt_fiware_issue_not_found) }, status: :not_found
    elsif !issue.visible?
      render json: { error: l(:gtt_fiware_issue_forbidden) }, status: :forbidden
    else
      @issue = issue
    end
  end

  # Ensure the NGSI plugin is enabled for the project.
  def plugin_enabled?
    @project = @issue.project
    unless @project.module_enabled?('gtt_fiware')
      render json: { error: l(:gtt_fiware_error_plugin_not_enabled) }, status: :forbidden
    end
  end

  # Render the ngsi/issue template with the appropriate locals
  def render_issue_template
    respond_to do |format|
      format.jsonld { render template: 'ngsi/issue', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/issue', locals: { ngsiv2: true } }
    end
  end
end
