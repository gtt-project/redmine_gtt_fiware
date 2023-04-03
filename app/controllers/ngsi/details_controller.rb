class Ngsi::DetailsController < Ngsi::BaseController
  before_action :set_detail, only: [:show]

  def show
    presenter = DetailPresenter.new(@detail, @normalized, request.format.symbol == :json, view_context)
    render json: presenter
  end

  private

  def set_detail
    @detail = JournalDetail.find_by(id: params[:id])
    render json: { error: t('gtt_fiware.detail_not_found') }, status: :not_found unless @detail
  end
end
