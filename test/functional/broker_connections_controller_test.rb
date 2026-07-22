require File.expand_path('../../test_helper', __FILE__)

class BrokerConnectionsControllerTest < ActionController::TestCase
  fixtures :users, :email_addresses

  def setup
    @request.session[:user_id] = 1 # admin
  end

  def connection_params(overrides = {})
    {
      name: 'City broker',
      standard: 'NGSI-LD',
      url: 'https://broker.example.com',
      context: 'https://broker.example.com/context.jsonld',
      auth_mode: 'stored',
      auth_token: 'secret-token'
    }.merge(overrides)
  end

  def test_index_requires_admin
    @request.session[:user_id] = 2 # jsmith, not an admin
    get :index
    assert_response :forbidden
  end

  def test_index_lists_connections
    BrokerConnection.create!(connection_params)
    get :index
    assert_response :success
    assert_select 'td.name', text: 'City broker'
  end

  def test_create_persists_and_ciphers_the_token
    assert_difference 'BrokerConnection.count', 1 do
      post :create, params: { broker_connection: connection_params }
    end
    connection = BrokerConnection.order(id: :desc).first
    assert_equal 'City broker', connection.name
    assert_equal 'secret-token', connection.auth_token
  end

  def test_create_rejects_invalid_service
    assert_no_difference 'BrokerConnection.count' do
      post :create, params: { broker_connection: connection_params(fiware_service: "smart'city") }
    end
    assert_response :success # re-renders the form with errors
  end

  # A blank token on update keeps the stored one; the form never renders it.
  def test_update_with_blank_token_keeps_the_stored_token
    connection = BrokerConnection.create!(connection_params)
    put :update, params: { id: connection.id, broker_connection: { name: 'Renamed', auth_token: '' } }
    assert_redirected_to broker_connections_path
    connection.reload
    assert_equal 'Renamed', connection.name
    assert_equal 'secret-token', connection.auth_token
  end

  def test_update_with_a_new_token_replaces_it
    connection = BrokerConnection.create!(connection_params)
    put :update, params: { id: connection.id, broker_connection: { auth_token: 'rotated' } }
    assert_equal 'rotated', connection.reload.auth_token
  end

  def test_destroy_removes_an_unreferenced_connection
    connection = BrokerConnection.create!(connection_params)
    assert_difference 'BrokerConnection.count', -1 do
      delete :destroy, params: { id: connection.id }
    end
    assert_redirected_to broker_connections_path
  end

  def test_edit_form_does_not_leak_the_stored_token
    connection = BrokerConnection.create!(connection_params)
    get :edit, params: { id: connection.id }
    assert_response :success
    assert_not_includes response.body, 'secret-token'
    assert_not_includes response.body, connection.read_attribute(:auth_token).to_s
  end
end
