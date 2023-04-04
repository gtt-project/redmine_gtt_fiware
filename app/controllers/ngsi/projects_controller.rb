module Ngsi
  class ProjectsController < BaseController
    before_action :set_project, only: [:show]
    before_action :plugin_enabled?, only: [:show]

    def show
      presenter = ProjectPresenter.new(@project, @normalized, request.format.symbol == :json, view_context)
      render json: presenter
    end

    private

    def set_project
      @project = Project.find_by(id: params[:id])
      render json: { error: t('gtt_fiware.project_not_found') }, status: :not_found unless @project
    end

    def plugin_enabled?
      unless @project.module_enabled?('gtt_fiware')
        render json: { error: t('gtt_fiware.error_plugin_not_enabled') }, status: :forbidden
      end
    end
  end
end
