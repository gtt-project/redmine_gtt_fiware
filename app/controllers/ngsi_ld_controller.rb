class NgsiLdController < ApplicationController

  before_action :authorize_global

  accept_api_auth :context, :data_model

  def context
    respond_to do |format|
      format.jsonld { render template: "ngsi_ld/context/core" }
    end
  end

  def data_model
    if ['project','tracker','user','version'].include?(params[:type])
      respond_to do |format|
        format.jsonld { render template: "ngsi_ld/context/#{params[:type]}" }
      end
    end
  end

end
