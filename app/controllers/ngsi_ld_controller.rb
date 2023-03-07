class NgsiLdController < ApplicationController

  before_action :authorize_global

  accept_api_auth :context, :data_model

  def context
    respond_to do |format|
      format.jsonld { render }
    end
  end

  def data_model
    respond_to do |format|
      format.jsonld { render template: "ngsi_ld/tracker" }
    end
  end

end
