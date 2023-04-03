class Ngsi::IssuesController < Ngsi::BaseController
  before_action :find_issue, only: [:show]
  before_action :plugin_enabled?, only: [:show]

  def show
    presenter = IssuePresenter.new(@issue, @normalized, request.format.symbol == :json, view_context)
    render json: presenter
  end

  private

  def find_issue
    @issue = Issue.find_by(id: params[:id])
    render json: { error: t('gtt_fiware.issue_not_found') }, status: :not_found unless @issue
  end

  def plugin_enabled?
    @project = @issue.project
    render json: { error: t('gtt_fiware.error_plugin_not_enabled') }, status: :forbidden unless @project.module_enabled?('gtt_fiware')
  end
end
