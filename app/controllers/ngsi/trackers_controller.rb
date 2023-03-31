class Ngsi::TrackersController < Ngsi::BaseController
  before_action :set_tracker, only: [:show]

  def show
    render_tracker_template
  end

  private

  def set_tracker
    tracker = Tracker.find_by(id: params[:id])

    if tracker.nil?
      render json: { error: l(:gtt_fiware_tracker_not_found) }, status: :not_found
    else
      @tracker = tracker
    end
  end

  def render_tracker_template
    respond_to do |format|
      format.jsonld { render template: 'ngsi/tracker', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/tracker', locals: { ngsiv2: true } }
    end
  end
end
