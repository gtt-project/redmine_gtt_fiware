# Ngsi::IssuesController handles the NGSI JSON-LD and NGSIv2 issue requests.
# It inherits from Ngsi::BaseController and provides actions
# for handling issue-related endpoints.
class Ngsi::IssuesController < Ngsi::BaseController
  before_action :set_issue, only: [:show]

  # Processes the issue request and renders the JSON-LD or NGSIv2 representation.
  def show
    respond_to do |format|
      format.jsonld { render_issue_template(ngsiv2: false) }
      format.json   { render_issue_template(ngsiv2: true) }
    end
  end

  private

  # Set the @issue based on the ID parameter and handle errors if the issue is not found
  def set_issue
    @issue = Issue.find_by(id: params[:id])

    if @issue.nil?
      render json: { error: "Issue not found" }, status: :not_found
    end
  end

  # Render the ngsi/issue template with the given locals
  def render_issue_template(locals)
    render template: 'ngsi/issue', locals: locals
  end
end
