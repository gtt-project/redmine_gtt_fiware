class Ngsi::PrioritiesController < Ngsi::BaseController
  before_action :set_priority, only: [:show]

  def show
    render_priority_template
  end

  private

  def set_priority
    priority = IssuePriority.find_by(id: params[:id])

    if priority.nil?
      render json: { error: l(:gtt_fiware_priority_not_found) }, priority: :not_found
    else
      @priority = priority
    end
  end

  def render_priority_template
    respond_to do |format|
      format.jsonld { render template: 'ngsi/priority', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/priority', locals: { ngsiv2: true } }
    end
  end
end
