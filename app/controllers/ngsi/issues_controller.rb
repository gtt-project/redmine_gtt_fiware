class Ngsi::IssuesController < Ngsi::BaseController

  def show
    @issue = Issue.find(params[:id])

    # Make sure the @issue object is not nil
    if @issue.nil?
      # Handle the error, e.g., render a 404 Not Found response
      render json: { error: "Issue not found" }, status: :not_found
      return
    end

    # Get the "normalized" query parameter or set it to the value from the plugin setting
    @normalized = if params.key?(:normalized)
      to_boolean(params[:normalized])
    else
      to_boolean(Setting.plugin_redmine_gtt_fiware['ngsi_ld_format'])
    end

    respond_to do |format|
      format.jsonld { render template: 'ngsi/issue', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/issue', locals: { ngsiv2: true  } }
    end

  end

end
