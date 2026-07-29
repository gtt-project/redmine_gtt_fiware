# Instance-level CRUD for broker connections (#67), admin-only like core's
# auth sources. Connections hold the broker URL, standard, tenant headers and
# auth; subscription templates reference them.
class BrokerConnectionsController < ApplicationController
  layout 'admin'
  self.main_menu = false

  # Redmine's ApplicationController already enables forgery protection; this
  # explicit call makes it visible to static analysis (CodeQL cannot see the
  # parent class, which lives outside the plugin repository) and pins the
  # strategy to :exception for this admin-only form controller.
  protect_from_forgery with: :exception

  before_action :require_admin
  before_action :find_broker_connection, only: [:edit, :update, :destroy]

  def index
    # Preloaded so the per-connection template count renders without an extra
    # query per row.
    @broker_connections = BrokerConnection.sorted.includes(:subscription_templates)
  end

  def new
    @broker_connection = BrokerConnection.new
  end

  def create
    @broker_connection = BrokerConnection.new(broker_connection_params)
    if @broker_connection.save
      sync_emission_mappings
      flash[:notice] = l(:notice_successful_create)
      redirect_to broker_connections_path
    else
      render :new
    end
  end

  def edit; end

  def update
    if @broker_connection.update(broker_connection_params)
      sync_emission_mappings
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

  # Issue emission mapping rows (#69): one checkbox + subtype per tracker on
  # the connection form, serialized as emission_mappings[<tracker_id>].
  # Rows are synced after the connection saved; a row that fails validation
  # (bad subtype term) is reported in the flash rather than blocking the
  # connection itself.
  def sync_emission_mappings
    rows = params[:emission_mappings]
    return unless rows.is_a?(ActionController::Parameters)

    failed = []
    rows.each do |tracker_id, attrs|
      mapping = @broker_connection.emission_mappings.find_or_initialize_by(tracker_id: tracker_id)
      if attrs[:enabled] == '1'
        mapping.subtype = attrs[:subtype].to_s.strip
        # The setter intersects with the catalog, so unknown keys are dropped.
        mapping.exposed_standard_fields = Array(attrs[:fields]).map(&:to_s)
        custom = {}
        (attrs[:custom] || {}).each do |cf_id, cf_attrs|
          custom[cf_id] = cf_attrs[:term].to_s.strip if cf_attrs[:enabled] == '1'
        end
        mapping.exposed_custom_fields = custom
        failed << mapping unless mapping.save
      elsif mapping.persisted?
        mapping.destroy
      end
    end
    return if failed.empty?

    flash[:error] = failed.map do |mapping|
      "#{mapping.tracker&.name}: #{mapping.errors.full_messages.join(', ')}"
    end.join('; ')
  end

  def broker_connection_params
    permitted = params.require(:broker_connection)
                      .permit(:name, :standard, :url, :fiware_service, :fiware_servicepath,
                              :context, :auth_mode, :auth_token, :token_header, :throttling)
    # A blank token on edit means "keep the stored token"; the form never
    # renders the current one.
    permitted.delete(:auth_token) if permitted[:auth_token].blank?
    permitted
  end
end
