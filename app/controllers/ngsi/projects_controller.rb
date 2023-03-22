# Ngsi::ProjectsController handles the NGSI JSON-LD and NGSIv2 project requests.
# It inherits from Ngsi::BaseController and provides actions
# for handling project-related endpoints.
class Ngsi::ProjectsController < Ngsi::BaseController
  before_action :set_project, only: [:show]

  # Processes the project request and renders the JSON-LD or NGSIv2 representation.
  def show
    respond_to do |format|
      format.jsonld { render_project_template(ngsiv2: false) }
      format.json   { render_project_template(ngsiv2: true) }
    end
  end

  private

  # Set the @project based on the ID parameter and handle errors if the project is not found
  def set_project
    @project = Project.find_by(id: params[:id])

    if @project.nil?
      render json: { error: "Project not found" }, status: :not_found
    end
  end

  # Render the ngsi/project template with the given locals
  def render_project_template(locals)
    render template: 'ngsi/project', locals: locals
  end
end
