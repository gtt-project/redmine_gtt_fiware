class Ngsi::VersionsController < Ngsi::BaseController
  before_action :set_version, only: [:show]

  def show
    presenter = VersionPresenter.new(@version, @normalized, request.format.symbol == :json, view_context)
    render json: presenter
  end

  private

  def set_version
    @version = Version.find_by(id: params[:id])
    render json: { error: t('gtt_fiware.version_not_found') }, status: :not_found unless @version
  end
end
