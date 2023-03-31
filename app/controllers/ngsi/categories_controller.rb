class Ngsi::CategoriesController < Ngsi::BaseController
  before_action :set_category, only: [:show]

  def show
    render_category_template
  end

  private

  def set_category
    category = IssueCategory.find_by(id: params[:id])

    if category.nil?
      render json: { error: l(:gtt_fiware_category_not_found) }, category: :not_found
    else
      @category = category
    end
  end

  def render_category_template
    respond_to do |format|
      format.jsonld { render template: 'ngsi/category', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/category', locals: { ngsiv2: true } }
    end
  end
end
