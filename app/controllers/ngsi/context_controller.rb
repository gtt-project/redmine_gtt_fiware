# Ngsi::ContextController handles the JSON-LD context requests.
# It inherits from ApplicationController and provides actions
# for handling context-related endpoints.
class Ngsi::ContextController < ApplicationController
  # Require global authorization before processing any action
  before_action :authorize_global

  # Allow API access to the context action
  accept_api_auth :context

  # Processes the context request based on the type parameter.
  # Renders the appropriate JSON-LD context template for the requested type.
  def index
    respond_to do |format|
      format.jsonld { render template: "ngsi/context/#{context_template}" }
    end
  end

  private

  # Determine the context template to render based on the type parameter
  def context_template
    if params[:type].present? && valid_types.include?(params[:type])
      params[:type]
    else
      'redmine'
    end
  end

  # Define a list of valid context types
  def valid_types
    %w[issues projects users gtt]
  end
end
