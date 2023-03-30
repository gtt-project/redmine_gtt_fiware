class Ngsi::VersionsController < Ngsi::BaseController
  before_action :set_version, only: [:show]

  def show
    render_version_template
  end

  private

  def set_version
    version = Version.find_by(id: params[:id])

    if version.nil?
      render json: { error: l(:gtt_fiware_version_not_found) }, status: :not_found
    else
      @version = version
    end
  end

  def render_version_template
    respond_to do |format|
      format.jsonld { render template: 'ngsi/version', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/version', locals: { ngsiv2: true } }
    end
  end
end
