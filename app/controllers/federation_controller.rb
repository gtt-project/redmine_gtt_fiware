# The issue-page federation panel (#70, 4b): other organizations' Issue
# entities referring to the same source entity, fetched asynchronously so a
# slow broker never delays the issue page itself.
class FederationController < ApplicationController
  # See SubscriptionIssuesController: the explicit declaration keeps the
  # framework-default forgery protection visible to static analysis.
  protect_from_forgery with: :exception

  before_action :find_issue

  def show
    connection = @issue.subscription_template&.broker_connection
    unless @issue.fiware_entity.present? && connection&.ngsi_ld?
      head :no_content
      return
    end

    @siblings = RedmineGttFiware::FederationSiblings.new(connection).for_entity(@issue.fiware_entity)
    if @siblings.empty?
      head :no_content
    else
      render partial: 'federation/siblings', layout: false
    end
  end

  private

  # Standard issue visibility: the panel shows broker data correlated to the
  # issue, so seeing the issue is the requirement.
  def find_issue
    @issue = Issue.find(params[:id])
    render_404 unless @issue.visible?(User.current)
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
