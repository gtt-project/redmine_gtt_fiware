require File.expand_path('../../test_helper', __FILE__)

class FiwareEntitiesControllerTest < ActionController::TestCase
  fixtures :projects, :trackers, :projects_trackers, :issue_statuses,
           :users, :email_addresses, :members, :member_roles, :roles,
           :enumerations, :issues

  INSTANCE_SETTINGS = { 'fiware_instance_id' => 'test-town' }.freeze

  def setup
    @request.session[:user_id] = 1
    @issue = Issue.find(1)
  end

  def test_serves_the_core_representation_without_a_mapping
    with_settings plugin_redmine_gtt_fiware: INSTANCE_SETTINGS do
      get :show, params: { id: @issue.id }
    end
    assert_response :success
    assert_equal 'application/ld+json', response.media_type
    entity = JSON.parse(response.body)
    assert_equal "urn:ngsi-ld:Issue:redmine:test-town:#{@issue.id}", entity['id']
    assert_equal 'Issue', entity['type']
    assert_equal @issue.subject, entity.dig('title', 'value')
    assert_nil entity['subtype'], 'no mapping, no subtype'
  end

  def test_serves_the_curated_representation_with_a_mapping
    connection = BrokerConnection.create!(
      name: 'Entity endpoint broker', standard: 'NGSI-LD',
      url: 'https://broker.example.com', auth_mode: 'stored'
    )
    mapping = EmissionMapping.create!(broker_connection: connection,
                                      tracker: @issue.tracker, subtype: 'WorkOrder')
    mapping.exposed_standard_fields = %w[priority]
    mapping.save!

    with_settings plugin_redmine_gtt_fiware: INSTANCE_SETTINGS do
      get :show, params: { id: @issue.id }
    end
    assert_response :success
    entity = JSON.parse(response.body)
    assert_equal 'WorkOrder', entity.dig('subtype', 'value')
    assert_equal @issue.priority.name, entity.dig('priority', 'value')
  end

  # Entity ids embed the instance identifier; without one there is no valid
  # representation to serve.
  def test_not_found_without_an_instance_id
    with_settings plugin_redmine_gtt_fiware: { 'fiware_instance_id' => '' } do
      get :show, params: { id: @issue.id }
    end
    assert_response :not_found
  end

  def test_requires_issue_visibility
    @issue.project.update_column(:is_public, false)
    @request.session[:user_id] = nil
    with_settings plugin_redmine_gtt_fiware: INSTANCE_SETTINGS, login_required: '0' do
      get :show, params: { id: @issue.id }
    end
    assert_response :not_found
  end
end
