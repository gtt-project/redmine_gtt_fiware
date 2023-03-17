# Ngsi::IssuesController handles the NGSI JSON-LD and NGSIv2 issue requests.
# It inherits from Ngsi::BaseController and provides actions
# for handling issue-related endpoints.
class Ngsi::IssuesController < Ngsi::BaseController

  # Processes the issue request and renders the JSON-LD or NGSIv2 representation.
  def show
    # Find the issue by its ID
    @issue = Issue.find(params[:id])

    # Make sure the @issue object is not nil
    if @issue.nil?
      # Handle the error, e.g., render a 404 Not Found response
      render json: { error: "Issue not found" }, status: :not_found
      return
    end

    # Render the appropriate template based on the requested format
    respond_to do |format|
      format.jsonld { render template: 'ngsi/issue', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/issue', locals: { ngsiv2: true  } }
    end
  end

end
