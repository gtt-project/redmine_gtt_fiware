module Ngsi
  class RelationsController < BaseController
    before_action :set_relation, only: [:show]

    def show
      presenter = RelationPresenter.new(@relation, @normalized, request.format.symbol == :json, view_context)
      render json: presenter
    end

    private

    def set_relation
      @relation = IssueRelation.find_by(id: params[:id])
      render json: { error: t('gtt_fiware.relation_not_found') }, status: :not_found unless @relation
    end
  end
end
