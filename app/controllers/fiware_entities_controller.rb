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

    entity = RedmineGttFiware::IssueEntity.new(@issue, mapping_for(@issue)).to_h
    render json: entity, content_type: 'application/ld+json'
  end

  private

  # A tracker can be mapped on several connections with different subtypes
  # and exposure. The on-demand representation uses the mapping of the
  # issue's own connection when the issue came from a broker, the oldest
  # mapping otherwise - deterministic, and consistent with the broker the
  # issue is actually correlated with.
  def mapping_for(issue)
    mappings = EmissionMapping.where(tracker_id: issue.tracker_id).order(:id)
    preferred = issue.subscription_template&.broker_connection_id
    mappings.detect { |m| m.broker_connection_id == preferred } || mappings.first
  end

  def find_issue
    @issue = Issue.find(params[:id])
    render_404 unless @issue.visible?(User.current)
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
