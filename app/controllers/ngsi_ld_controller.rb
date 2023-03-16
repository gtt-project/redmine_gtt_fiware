class NgsiLdController < ApplicationController

  before_action :authorize_global

  accept_api_auth :context

  def context
    if params[:type].present? && ['issues','projects','users','gtt'].include?(params[:type])
      respond_to do |format|
        format.jsonld { render template: "ngsi_ld/context/#{params[:type]}" }
      end
    else
      respond_to do |format|
        format.jsonld { render template: "ngsi_ld/context/redmine" }
      end
    end
  end

end
