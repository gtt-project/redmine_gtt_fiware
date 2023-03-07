class NgsiLdController < ApplicationController

  before_action :authorize_global

  accept_api_auth :context, :data_model

  def context
    respond_to do |format|
      format.jsonld { render jsonld: nil }
    end
  end

  def data_model
    respond_to do |format|
      format.jsonld { render json: JSON.pretty_generate(get_data_model), layout: false }
    end
  end

  private

  def get_data_model
    return {
      "tracker_id": params[:tracker_id]
    }
  end

end
