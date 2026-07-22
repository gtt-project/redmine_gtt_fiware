# Instance-level CRUD for broker connections (#67), admin-only like core's
# auth sources. Connections hold the broker URL, standard, tenant headers and
# auth; subscription templates reference them.
class BrokerConnectionsController < ApplicationController
  layout 'admin'
  self.main_menu = false

  before_action :require_admin
  before_action :find_broker_connection, only: [:edit, :update, :destroy]

  def index
    @broker_connections = BrokerConnection.sorted
  end

  def new
    @broker_connection = BrokerConnection.new
  end

  def create
    @broker_connection = BrokerConnection.new(broker_connection_params)
    if @broker_connection.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to broker_connections_path
    else
      render :new
    end
  end

  def edit; end

  def update
    if @broker_connection.update(broker_connection_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to broker_connections_path
    else
      render :edit
    end
  end

  def destroy
    if @broker_connection.destroy
      flash[:notice] = l(:notice_successful_delete)
    else
      flash[:error] = @broker_connection.errors.full_messages.join(', ')
    end
    redirect_to broker_connections_path
  end

  private

  def find_broker_connection
    @broker_connection = BrokerConnection.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def broker_connection_params
    permitted = params.require(:broker_connection)
                      .permit(:name, :standard, :url, :fiware_service, :fiware_servicepath,
                              :context, :auth_mode, :auth_token)
    # A blank token on edit means "keep the stored token"; the form never
    # renders the current one.
    permitted.delete(:auth_token) if permitted[:auth_token].blank?
    permitted
  end
end
