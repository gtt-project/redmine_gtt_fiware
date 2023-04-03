class Ngsi::IssuesController < Ngsi::BaseController
  before_action :find_issue, only: [:show, :update, :destroy]
  before_action :plugin_enabled?, only: [:show, :create, :update, :destroy]

  accept_api_auth :show, :destroy
  protect_from_forgery except: [:destroy]

  def show
    presenter = IssuePresenter.new(@issue, @normalized, request.format.symbol == :json, view_context)
    render json: presenter
  end

  def create
    # TODO: implement the create action
  end

  def update
    # TODO: implement the update action
  end

  def destroy
    if @issue.destroy
      head :no_content
    else
      render json: { error: t('gtt_fiware.issue_deletion_error') }, status: :unprocessable_entity
    end
  end

  private

  def find_issue
    @issue = Issue.find_by(id: params[:id])
    render json: { error: t('gtt_fiware.issue_not_found') }, status: :not_found unless @issue
  end

  def plugin_enabled?
    @project = @issue ? @issue.project : Project.find_by(id: params[:issue][:projectId])
    render json: { error: t('gtt_fiware.error_plugin_not_enabled') }, status: :forbidden unless @project.module_enabled?('gtt_fiware')
  end

  def verified_request?
    super || valid_authenticity_token?(session, request.headers['X-CSRF-Token'])
  end
end
