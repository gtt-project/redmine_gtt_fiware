# Ngsi::IssuesController handles the NGSI JSON-LD and NGSIv2 issue requests.
# It inherits from Ngsi::BaseController and provides actions
# for handling issue-related endpoints.
class Ngsi::IssuesController < Ngsi::BaseController
  before_action :find_issue, only: [:show]

  # Processes the issue request and renders the JSON-LD or NGSIv2 representation.
  def show
    render_issue_template
  end

  private

  # Set the @issue based on the ID parameter and handle errors if the issue is not found
  def find_issue
    @issue = Issue.visible.find_by(id: params[:id])
    return if @issue.present?

    render json: { error: "Issue not found" }, status: :not_found
  end

  # Render the ngsi/issue template with the appropriate locals
  def render_issue_template
    respond_to do |format|
      format.jsonld { render template: 'ngsi/issue', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/issue', locals: { ngsiv2: true } }
    end
  end
end
