# Serves a single issue as an NGSI-LD entity (#4): the same representation
# the emitter publishes, available on demand. With an emission mapping for
# the issue's tracker the full curated representation is rendered; without
# one, the frozen core alone.
class FiwareEntitiesController < ApplicationController
  # See SubscriptionIssuesController: the explicit declaration keeps the
  # framework-default forgery protection visible to static analysis.
  protect_from_forgery with: :exception

  accept_api_auth :show
  before_action :find_issue

  def show
    # Entity ids embed the instance identifier; without one there is no
    # valid representation to serve.
    if RedmineGttFiware::Emitter.instance_id.blank?
      head :not_found
      return
    end

    mapping = EmissionMapping.joins(:broker_connection)
                             .where(tracker_id: @issue.tracker_id)
                             .order(:id).first
    entity = RedmineGttFiware::IssueEntity.new(@issue, mapping).to_h
    render json: entity, content_type: 'application/ld+json'
  end

  private

  def find_issue
    @issue = Issue.find(params[:id])
    render_404 unless @issue.visible?(User.current)
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
