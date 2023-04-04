module Ngsi
  class CategoriesController < BaseController
    before_action :set_category, only: [:show]

    def show
      presenter = CategoryPresenter.new(@category, @normalized, request.format.symbol == :json, view_context)
      render json: presenter
    end

    private

    def set_category
      @category = IssueCategory.find_by(id: params[:id])
      render json: { error: t('gtt_fiware.category_not_found') }, status: :not_found unless @category
    end
  end
end
