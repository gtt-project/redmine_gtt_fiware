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
  # or not visible based on permissions.
  def set_user
    user = User.find_by(id: params[:id])

    if user.nil?
      render json: { error: l(:gtt_fiware_user_not_found) }, status: :not_found
    elsif !user.visible?
      render json: { error: l(:gtt_fiware_user_forbidden) }, status: :forbidden
    else
      @user = user
    end
  end

  # Render the ngsi/user template with the appropriate locals
  def render_user_template
    respond_to do |format|
      format.jsonld { render template: 'ngsi/user', locals: { ngsiv2: false } }
      format.json   { render template: 'ngsi/user', locals: { ngsiv2: true } }
    end
  end
end
