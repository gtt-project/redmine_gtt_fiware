class Ngsi::DetailsController < Ngsi::BaseController
  before_action :set_detail, only: [:show]

  def show
    render_detail_template
  end

  private

  def set_detail
    detail = JournalDetail.find_by(id: params[:id])

    if detail.nil?
      render json: { error: l(:gtt_fiware_detail_not_found) }, detail: :not_found
    else
      @detail = detail
    end
  end

  def render_detail_template
    respond_to do |format|
      format.jsonld { render template: 'ngsi/detail', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/detail', locals: { ngsiv2: true } }
    end
  end
end
