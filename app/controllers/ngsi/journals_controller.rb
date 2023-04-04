module Ngsi
  class JournalsController < BaseController
    before_action :set_journal, only: [:show]

    def show
      presenter = JournalPresenter.new(@journal, @normalized, request.format.symbol == :json, view_context)
      render json: presenter
    end

    private

    def set_journal
      @journal = Journal.find_by(id: params[:id])
      render json: { error: t('gtt_fiware.journal_not_found') }, status: :not_found unless @journal
    end
  end
end
