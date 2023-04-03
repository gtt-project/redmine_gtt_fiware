class Ngsi::UsersController < Ngsi::BaseController
  before_action :set_user, only: [:show]

  def show
    presenter = UserPresenter.new(@user, @normalized, request.format.symbol == :json, view_context)
    render json: presenter
  end

  private

  def set_user
    @user = User.find_by(id: params[:id])
    render json: { error: t('gtt_fiware.user_not_found') }, status: :not_found unless @user
  end
end
