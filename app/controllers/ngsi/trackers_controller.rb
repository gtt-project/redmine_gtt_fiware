module Ngsi
  class TrackersController < BaseController
    before_action :set_tracker, only: [:show]

    def show
      presenter = TrackerPresenter.new(@tracker, @normalized, request.format.symbol == :json, view_context)
      render json: presenter
    end

    private

    def set_tracker
      @tracker = Tracker.find_by(id: params[:id])
      render json: { error: t('gtt_fiware.tracker_not_found') }, status: :not_found unless @tracker
    end
  end
end
