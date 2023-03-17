# Ngsi::UsersController handles the NGSI JSON-LD and NGSIv2 user requests.
# It inherits from Ngsi::BaseController and provides actions
# for handling user-related endpoints.
class Ngsi::UsersController < Ngsi::BaseController

  # Processes the user request and renders the JSON-LD or NGSIv2 representation.
  def show
    # Find the user by its ID
    @user = User.find(params[:id])

    # Make sure the @user object is not nil
    if @user.nil?
      # Handle the error, e.g., render a 404 Not Found response
      render json: { error: "User not found" }, status: :not_found
      return
    end

    # Render the appropriate template based on the requested format
    respond_to do |format|
      format.jsonld { render template: 'ngsi/user', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/user', locals: { ngsiv2: true  } }
    end
  end

end
