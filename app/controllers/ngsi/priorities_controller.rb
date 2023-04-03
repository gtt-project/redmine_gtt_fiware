class Ngsi::PrioritiesController < Ngsi::BaseController
  before_action :set_priority, only: [:show]

  def show
    presenter = PriorityPresenter.new(@priority, @normalized, request.format.symbol == :json, view_context)
    render json: presenter
  end

  private

  def set_priority
    @priority = IssuePriority.find_by(id: params[:id])
    render json: { error: t('gtt_fiware.priority_not_found') }, status: :not_found unless @priority
  end
end
