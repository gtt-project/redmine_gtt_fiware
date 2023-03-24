# Ngsi::ProjectsController handles the NGSI JSON-LD and NGSIv2 project requests.
# It inherits from Ngsi::BaseController and provides actions
# for handling project-related endpoints.
class Ngsi::ProjectsController < Ngsi::BaseController
  before_action :set_project, only: [:show]
  before_action :plugin_enabled?, only: [:show]

  # Processes the project request and renders the JSON-LD or NGSIv2 representation.
  def show
    render_project_template
  end

  private

  # Set the @project based on the ID parameter and handle errors if the project is not found
  def set_project
    @project = Project.visible.find_by(id: params[:id])
    return if @project.present?

    render json: { error: l(:gtt_fiware_project_not_found) }, status: :not_found
  end

  # Ensure the NGSI plugin is enabled for the project.
  def plugin_enabled?
    unless @project.module_enabled?('gtt_fiware')
      render json: { error: l(:gtt_fiware_error_plugin_not_enabled) }, status: :forbidden
    end
  end

  # Render the ngsi/project template with the appropriate locals
  def render_project_template
    respond_to do |format|
      format.jsonld { render template: 'ngsi/project', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/project', locals: { ngsiv2: true } }
    end
  end
end
