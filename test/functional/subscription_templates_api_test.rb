require File.expand_path('../../test_helper', __FILE__)

# The subscription REST API (#22). Uses an integration test so the request
# really goes through routing, format negotiation and API key auth.
class SubscriptionTemplatesApiTest < Redmine::IntegrationTest
  fixtures :projects, :trackers, :projects_trackers, :issue_statuses, :users,
           :email_addresses, :members, :member_roles, :roles, :enumerations,
           :enabled_modules

  def setup
    Setting.rest_api_enabled = '1'
    @project = Project.find(1)
    @project.enabled_module_names = @project.enabled_module_names | ['gtt_fiware']
    Role.find(1).add_permission!(:manage_subscription_templates)

    @user = User.find(2) # jsmith, manager of project 1
    @token = @user.api_key # generated on first read

    @connection = BrokerConnection.create!(
      name: 'API broker', standard: 'NGSIv2',
      url: 'https://broker.example.com', auth_mode: 'stored',
      auth_token: 'do-not-leak-me'
    )
    @template = SubscriptionTemplate.create!(
      broker_connection_id: @connection.id, status: 'active',
      name: 'API alerts', subject: 'Sensor ${id}',
      description: 'A monitored value changed',
      entities_string: '[{"idPattern": ".*", "type": "TemperatureSensor"}]',
      attrs: '["temperature"]',
      project_id: 1, tracker_id: 1, issue_status_id: 1,
      issue_priority_id: IssuePriority.first.id, member_id: 1
    )
  end

  def auth
    { 'X-Redmine-API-Key' => @token }
  end

  def json
    JSON.parse(response.body)
  end

  # --- reading --------------------------------------------------------------

  def test_index_lists_the_project_subscriptions
    get "/projects/#{@project.id}/subscription_templates.json", headers: auth
    assert_response :success
    assert_equal 'application/json', response.media_type
    assert_equal 1, json['total_count']
    entry = json['subscription_templates'].first
    assert_equal 'API alerts', entry['name']
    assert_equal({ 'id' => @connection.id, 'name' => 'API broker', 'standard' => 'NGSIv2' },
                 entry['broker_connection'])
    # Every association is rendered as an id/name reference.
    assert_equal({ 'id' => @project.id, 'name' => @project.name }, entry['project'])
    assert_equal({ 'id' => 1, 'name' => Tracker.find(1).name }, entry['tracker'])
    assert_equal({ 'id' => 1, 'name' => IssueStatus.find(1).name }, entry['issue_status'])
    assert_equal({ 'id' => 1, 'name' => Member.find(1).name }, entry['member'])
    # Associations that are not set are omitted rather than rendered as null.
    assert_not entry.key?('version')
    assert_not entry.key?('issue_category')
    assert_equal [{ 'idPattern' => '.*', 'type' => 'TemperatureSensor' }], entry['entities']
    assert_equal ['temperature'], entry['attrs']
    assert_equal false, entry['published']
  end

  def template_attributes(overrides = {})
    {
      broker_connection_id: @connection.id, status: 'active',
      subject: 'Sensor ${id}', description: 'A monitored value changed',
      entities_string: '[{"idPattern": ".*", "type": "TemperatureSensor"}]',
      project_id: @project.id, tracker_id: 1, issue_status_id: 1,
      issue_priority_id: IssuePriority.first.id, member_id: 1
    }.merge(overrides)
  end

  def test_index_paginates
    5.times { |i| SubscriptionTemplate.create!(template_attributes(name: "Extra #{i}")) }
    get "/projects/#{@project.id}/subscription_templates.json?limit=2&offset=1", headers: auth
    assert_response :success
    assert_equal 6, json['total_count']
    assert_equal 1, json['offset']
    assert_equal 2, json['limit']
    assert_equal 2, json['subscription_templates'].size
  end

  def test_show_returns_one_subscription
    get "/projects/#{@project.id}/subscription_templates/#{@template.id}.json", headers: auth
    assert_response :success
    assert_equal @template.id, json['subscription_template']['id']
    assert_equal 'Sensor ${id}', json['subscription_template']['subject']
  end

  def test_show_supports_xml
    get "/projects/#{@project.id}/subscription_templates/#{@template.id}.xml", headers: auth
    assert_response :success
    assert_equal 'application/xml', response.media_type
    assert_select 'subscription_template > name', text: 'API alerts'
  end

  # The webhook secret authenticates broker notifications: it must never leave
  # the server, and neither must the connection's stored broker token.
  def test_responses_never_expose_secrets
    get "/projects/#{@project.id}/subscription_templates.json", headers: auth
    assert_response :success
    assert_not_includes response.body, @template.reload.webhook_secret
    assert_not_includes response.body, 'webhook_secret'
    assert_not_includes response.body, 'do-not-leak-me'

    get "/projects/#{@project.id}/subscription_templates/#{@template.id}.json", headers: auth
    assert_not_includes response.body, @template.webhook_secret
    assert_not_includes response.body, 'do-not-leak-me'
  end

  # A subscription of another project is not reachable through this project's
  # collection, even for a user who may manage this one.
  def test_show_scopes_to_the_project
    other_project = Project.generate!
    other_project.enabled_module_names = other_project.enabled_module_names | ['gtt_fiware']
    other_project.trackers = [Tracker.find(1)]
    member = Member.create!(project: other_project, user: @user, roles: [Role.find(1)])
    foreign = SubscriptionTemplate.create!(
      template_attributes(name: 'Elsewhere', project_id: other_project.id, member_id: member.id)
    )

    get "/projects/#{@project.id}/subscription_templates/#{foreign.id}.json", headers: auth
    assert_response :not_found
  end

  # --- writing --------------------------------------------------------------

  def create_payload(overrides = {})
    {
      subscription_template: {
        broker_connection_id: @connection.id,
        name: 'Created over the API',
        subject: 'Sensor ${id}',
        description: 'Entity ${id} changed.',
        # API clients send structures where the form sends JSON strings.
        entities: [{ type: 'WasteContainer', idPattern: '.*' }],
        attrs: %w[fillingLevel temperature],
        tracker_id: 1,
        issue_status_id: 1,
        issue_priority_id: IssuePriority.first.id,
        member_id: 1
      }.merge(overrides)
    }
  end

  def test_create_accepts_structured_entities_and_attrs
    assert_difference 'SubscriptionTemplate.count', 1 do
      post "/projects/#{@project.id}/subscription_templates.json",
           params: create_payload.to_json,
           headers: auth.merge('CONTENT_TYPE' => 'application/json')
    end
    assert_response :created
    created = SubscriptionTemplate.order(id: :desc).first
    assert_equal 'Created over the API', created.name
    assert_equal [{ 'type' => 'WasteContainer', 'idPattern' => '.*' }], created.entities
    assert_equal %w[fillingLevel temperature], JSON.parse(created.attrs)
    # The response is the created resource, with a Location header.
    assert_equal created.id, json['subscription_template']['id']
    assert_match %r{/subscription_templates/#{created.id}\z}, response.headers['Location']
  end

  # Omitting alteration_types must leave the model default in place rather
  # than storing "no triggers" (the form's unchecked-box semantics).
  def test_create_keeps_the_default_alteration_types
    post "/projects/#{@project.id}/subscription_templates.json",
         params: create_payload.to_json,
         headers: auth.merge('CONTENT_TYPE' => 'application/json')
    assert_response :created
    assert_equal %w[entityCreate entityChange],
                 SubscriptionTemplate.order(id: :desc).first.alteration_types
    # And the create response renders them as an array of names, not the
    # serialized string the in-memory record still carries.
    assert_equal %w[entityCreate entityChange], json['subscription_template']['alteration_types']
  end

  def test_create_still_accepts_the_string_form
    post "/projects/#{@project.id}/subscription_templates.json",
         params: create_payload(entities: nil,
                                entities_string: '[{"type": "Room"}]',
                                attrs: '["temperature"]').to_json,
         headers: auth.merge('CONTENT_TYPE' => 'application/json')
    assert_response :created
    assert_equal [{ 'type' => 'Room' }], SubscriptionTemplate.order(id: :desc).first.entities
  end

  # geometry is a template, so the documented "${location}" placeholder is a
  # bare string rather than JSON; it must still be stored as the model's
  # JSON-encoded value instead of failing to parse.
  def test_create_accepts_the_geometry_placeholder
    post "/projects/#{@project.id}/subscription_templates.json",
         params: create_payload(geometry: '${location}').to_json,
         headers: auth.merge('CONTENT_TYPE' => 'application/json')
    assert_response :created
    assert_equal '${location}', SubscriptionTemplate.order(id: :desc).first.geometry
  end

  def test_create_accepts_geojson_geometry
    geojson = { 'type' => 'Point', 'coordinates' => [139.7, 35.68] }
    post "/projects/#{@project.id}/subscription_templates.json",
         params: create_payload(geometry: geojson).to_json,
         headers: auth.merge('CONTENT_TYPE' => 'application/json')
    assert_response :created
    assert_equal geojson, SubscriptionTemplate.order(id: :desc).first.geometry
  end

  # The project comes from the route: a project_id in the payload must not
  # move the subscription somewhere else, on create or on update.
  def test_create_ignores_a_project_id_in_the_payload
    other_project = Project.generate!
    post "/projects/#{@project.id}/subscription_templates.json",
         params: create_payload(project_id: other_project.id).to_json,
         headers: auth.merge('CONTENT_TYPE' => 'application/json')
    assert_response :created
    assert_equal @project.id, SubscriptionTemplate.order(id: :desc).first.project_id
  end

  def test_update_ignores_a_project_id_in_the_payload
    other_project = Project.generate!
    put "/projects/#{@project.id}/subscription_templates/#{@template.id}.json",
        params: { subscription_template: { project_id: other_project.id } }.to_json,
        headers: auth.merge('CONTENT_TYPE' => 'application/json')
    assert_response :no_content
    assert_equal @project.id, @template.reload.project_id
  end

  def test_create_reports_validation_errors
    assert_no_difference 'SubscriptionTemplate.count' do
      post "/projects/#{@project.id}/subscription_templates.json",
           params: create_payload(name: '').to_json,
           headers: auth.merge('CONTENT_TYPE' => 'application/json')
    end
    assert_response :unprocessable_entity
    assert json['errors'].any?
  end

  def test_update_changes_a_subscription
    put "/projects/#{@project.id}/subscription_templates/#{@template.id}.json",
        params: { subscription_template: { name: 'Renamed over the API' } }.to_json,
        headers: auth.merge('CONTENT_TYPE' => 'application/json')
    assert_response :no_content
    assert_equal 'Renamed over the API', @template.reload.name
  end

  def test_update_reports_validation_errors
    put "/projects/#{@project.id}/subscription_templates/#{@template.id}.json",
        params: { subscription_template: { name: '' } }.to_json,
        headers: auth.merge('CONTENT_TYPE' => 'application/json')
    assert_response :unprocessable_entity
    assert_equal 'API alerts', @template.reload.name
  end

  def test_destroy_removes_a_subscription
    assert_difference 'SubscriptionTemplate.count', -1 do
      delete "/projects/#{@project.id}/subscription_templates/#{@template.id}.json", headers: auth
    end
    assert_response :no_content
  end

  # --- authentication and authorization ------------------------------------

  def test_requests_without_credentials_are_rejected
    get "/projects/#{@project.id}/subscription_templates.json"
    assert_response :unauthorized
  end

  def test_requests_without_the_permission_are_rejected
    Role.find(1).remove_permission!(:manage_subscription_templates)
    get "/projects/#{@project.id}/subscription_templates.json", headers: auth
    assert_response :forbidden
  end

  def test_requests_are_rejected_when_the_module_is_disabled
    @project.enabled_module_names = @project.enabled_module_names - ['gtt_fiware']
    get "/projects/#{@project.id}/subscription_templates.json", headers: auth
    assert_response :forbidden
  end

  # --- html surfaces --------------------------------------------------------

  # index/show exist for the API; a browser is sent to the pages that show the
  # same data.
  def test_html_index_redirects_to_the_project_tab
    log_user('jsmith', 'jsmith')
    get "/projects/#{@project.id}/subscription_templates"
    assert_redirected_to "/projects/#{@project.identifier}/settings/subscription_templates"
  end

  def test_html_show_redirects_to_the_edit_form
    log_user('jsmith', 'jsmith')
    get "/projects/#{@project.id}/subscription_templates/#{@template.id}"
    assert_redirected_to "/projects/#{@project.identifier}/subscription_templates/#{@template.id}/edit"
  end
end
