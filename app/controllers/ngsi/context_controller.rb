class Ngsi::ContextController < ApplicationController

  before_action :authorize_global

  accept_api_auth :context

  def index
    if params[:type].present? && ['issues','projects','users','gtt'].include?(params[:type])
      respond_to do |format|
        format.jsonld { render template: "ngsi/context/#{params[:type]}" }
      end
    else
      respond_to do |format|
        format.jsonld { render template: "ngsi/context/redmine" }
      end
    end
  end

end
