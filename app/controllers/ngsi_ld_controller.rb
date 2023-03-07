class NgsiLdController < ApplicationController

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
