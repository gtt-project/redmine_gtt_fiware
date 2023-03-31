class Ngsi::JournalsController < Ngsi::BaseController
  before_action :set_journal, only: [:show]

  def show
    render_journal_template
  end

  private

  def set_journal
    journal = Journal.find_by(id: params[:id])

    if journal.nil?
      render json: { error: l(:gtt_fiware_journal_not_found) }, journal: :not_found
    else
      @journal = journal
    end
  end

  def render_journal_template
    respond_to do |format|
      format.jsonld { render template: 'ngsi/journal', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/journal', locals: { ngsiv2: true } }
    end
  end
end
