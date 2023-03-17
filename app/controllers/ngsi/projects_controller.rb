# Ngsi::ProjectsController handles the NGSI JSON-LD and NGSIv2 project requests.
# It inherits from Ngsi::BaseController and provides actions
# for handling project-related endpoints.
class Ngsi::ProjectsController < Ngsi::BaseController

  # Processes the project request and renders the JSON-LD or NGSIv2 representation.
  def show
    # Find the project by its ID
    @project = Project.find(params[:id])

    # Make sure the @project object is not nil
    if @project.nil?
      # Handle the error, e.g., render a 404 Not Found response
      render json: { error: "Project not found" }, status: :not_found
      return
    end

    # Render the appropriate template based on the requested format
    respond_to do |format|
      format.jsonld { render template: 'ngsi/project', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/project', locals: { ngsiv2: true  } }
    end
  end

end
