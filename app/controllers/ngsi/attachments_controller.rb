class Ngsi::AttachmentsController < Ngsi::BaseController
  before_action :set_attachment, only: [:show]

  def show
    render_attachment_template
  end

  private

  def set_attachment
    attachment = Attachment.find_by(id: params[:id])

    if attachment.nil?
      render json: { error: l(:gtt_fiware_attachment_not_found) }, status: :not_found
    else
      @attachment = attachment
    end
  end

  def render_attachment_template
    respond_to do |format|
      format.jsonld { render template: 'ngsi/attachment', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/attachment', locals: { ngsiv2: true } }
    end
  end
end
