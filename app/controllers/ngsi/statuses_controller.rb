class Ngsi::StatusesController < Ngsi::BaseController
  before_action :set_status, only: [:show]

  def show
    render_status_template
  end

  private

  def set_status
    status = IssueStatus.find_by(id: params[:id])

    if status.nil?
      render json: { error: l(:gtt_fiware_status_not_found) }, status: :not_found
    else
      @status = status
    end
  end

  def render_status_template
    respond_to do |format|
      format.jsonld { render template: 'ngsi/status', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/status', locals: { ngsiv2: true } }
    end
  end
end
