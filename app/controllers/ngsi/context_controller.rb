module Ngsi
  class ContextController < ApplicationController
    # Require global authorization before processing any action
    before_action :authorize_global

    # Allow API access to the context action
    accept_api_auth :index

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
      %w[attachments categories details gtt issues journals priorities projects relations statuses trackers versions users versions]
    end
  end
end
