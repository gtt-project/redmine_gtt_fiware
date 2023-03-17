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
    # Check if the type parameter is present and valid
    if params[:type].present? && ['issues', 'projects', 'users', 'gtt'].include?(params[:type])
      respond_to do |format|
        # Render the corresponding JSON-LD context template for the requested type
        format.jsonld { render template: "ngsi/context/#{params[:type]}" }
      end
    else
      # Render the default Redmine JSON-LD context template if no valid type is provided
      respond_to do |format|
        format.jsonld { render template: "ngsi/context/redmine" }
      end
    end
  end

end
