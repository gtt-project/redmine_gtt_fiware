# Ngsi::UsersController handles the NGSI JSON-LD and NGSIv2 user requests.
# It inherits from Ngsi::BaseController and provides actions
# for handling user-related endpoints.
class Ngsi::UsersController < Ngsi::BaseController
  before_action :set_user, only: [:show]

  # Processes the user request and renders the JSON-LD or NGSIv2 representation.
  def show
    render_user_template
  end

  private

  # Set the @user based on the ID parameter and handle errors if the user is not found
  def set_user
    @user = User.visible.find_by(id: params[:id])
    return if @user.present?

    render json: { error: "User not found" }, status: :not_found
  end

  # Render the ngsi/user template with the appropriate locals
  def render_user_template
    respond_to do |format|
      format.jsonld { render template: 'ngsi/user', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/user', locals: { ngsiv2: true } }
    end
  end
end
