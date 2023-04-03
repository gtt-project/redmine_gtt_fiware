class Ngsi::AttachmentsController < Ngsi::BaseController
  before_action :set_attachment, only: [:show]

  def show
    presenter = AttachmentPresenter.new(@attachment, @normalized, request.format.symbol == :json, view_context)
    render json: presenter
  end

  private

  def set_attachment
    @attachment = Attachment.find_by(id: params[:id])
    render json: { error: t('gtt_fiware.attachment_not_found') }, status: :not_found unless @attachment
  end
end
