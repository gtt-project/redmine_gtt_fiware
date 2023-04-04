module Ngsi
  class StatusesController < BaseController
    before_action :set_status, only: [:show]

    def show
      presenter = StatusPresenter.new(@status, @normalized, request.format.symbol == :json, view_context)
      render json: presenter
    end

    private

    def set_status
      @status = IssueStatus.find_by(id: params[:id])
      render json: { error: t('gtt_fiware.status_not_found') }, status: :not_found unless @status
    end
  end
end
