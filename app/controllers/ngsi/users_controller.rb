# Ngsi::UsersController handles the NGSI JSON-LD and NGSIv2 user requests.
# It inherits from Ngsi::BaseController and provides actions
# for handling user-related endpoints.
class Ngsi::UsersController < Ngsi::BaseController
  before_action :set_user, only: [:show]

  # Processes the user request and renders the JSON-LD or NGSIv2 representation.
  def show
    respond_to do |format|
      format.jsonld { render_user_template(ngsiv2: false) }
      format.json   { render_user_template(ngsiv2: true) }
    end
  end

  private

  # Set the @user based on the ID parameter and handle errors if the user is not found
  def set_user
    @user = User.find_by(id: params[:id])

    if @user.nil?
      render json: { error: "User not found" }, status: :not_found
    end
  end

  # Render the ngsi/user template with the given locals
  def render_user_template(locals)
    render template: 'ngsi/user', locals: locals
  end
end
