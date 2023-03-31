class Ngsi::RelationsController < Ngsi::BaseController
  before_action :set_relation, only: [:show]

  def show
    render_relation_template
  end

  private

  def set_relation
    relation = IssueRelation.find_by(id: params[:id])

    if relation.nil?
      render json: { error: l(:gtt_fiware_relation_not_found) }, relation: :not_found
    else
      @relation = relation
    end
  end

  def render_relation_template
    respond_to do |format|
      format.jsonld { render template: 'ngsi/relation', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/relation', locals: { ngsiv2: true } }
    end
  end
end
