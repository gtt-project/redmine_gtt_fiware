require File.expand_path('../../test_helper', __FILE__)

class SubscriptionTemplatesControllerTest < ActionController::TestCase
  fixtures :projects, :trackers, :issue_statuses, :users, :email_addresses,
           :members, :member_roles, :roles, :enumerations, :enabled_modules

  # A value that would break out of a single-quoted JavaScript string if
  # rendered unescaped.
  INJECTION = "'};alert('xss');//".freeze
  ESCAPED_INJECTION = "\\'};alert(\\'xss\\');//".freeze

  def setup
    @project = Project.find(1)
    @project.enabled_module_names = @project.enabled_module_names | ['gtt_fiware']
    Role.find(1).add_permission!(:manage_subscription_templates)

    # Browser auth mode: publish/unpublish render the JS flow (the pre-#67
    # behaviour) that these escaping tests exercise. The service value with a
    # quote exercises header escaping; BrokerConnection#fiware_service is
    # normally format-validated (#37), so it is written directly.
    @broker_connection = BrokerConnection.create!(
      name: 'Escaping broker',
      standard: 'NGSIv2',
      url: 'https://broker.example.com',
      auth_mode: 'browser'
    )
    @broker_connection.update_column(:fiware_service, "smart'city")

    @template = SubscriptionTemplate.create!(
      broker_connection_id: @broker_connection.id,
      status: 'active',
      name: 'Escaping test',
      subject: 'Sensor ${id}',
      description: 'A monitored value changed',
      notes: 'Latest reading: ${attrs.temperature.value}',
      # Since #64 the mapped fields (subject/description/notes/geometry/
      # attachments) are rendered plugin-side and never leave Redmine. The
      # entities selector still travels to the broker in the payload, so the
      # payload-escaping tests inject through it.
      entities_string: %([{"idPattern": "#{INJECTION}", "type": "TemperatureSensor"}]),
      project_id: 1,
      tracker_id: 1,
      issue_status_id: 1,
      issue_priority_id: IssuePriority.first.id,
      member_id: 1
    )
    @request.session[:user_id] = 2 # jsmith, manager of project 1
  end

  def test_publish_escapes_the_json_payload
    post :publish, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_response :success
    assert_not_includes response.body, INJECTION
    assert_includes response.body, ESCAPED_INJECTION
  end

  # The broker payload must carry the per-template webhook secret and must never
  # embed a Redmine API key.
  def test_publish_embeds_the_webhook_secret_and_no_api_key
    post :publish, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_response :success
    assert_includes response.body, 'X-Gtt-Webhook-Secret'
    assert_includes response.body, @template.reload.webhook_secret
    assert_not_includes response.body, 'X-Redmine-API-Key'
  end

  # The secret is stable across publishes: it must not change while a
  # subscription may be live on the broker (see the #81 follow-up).
  def test_publish_keeps_the_webhook_secret_stable
    original = @template.webhook_secret
    post :publish, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_response :success
    assert_equal original, @template.reload.webhook_secret
  end

  def test_publish_escapes_the_fiware_service_header
    post :publish, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_response :success
    assert_not_includes response.body, "'smart'city'"
    assert_includes response.body, "smart\\'city"
  end

  def test_unpublish_escapes_the_fiware_service_header
    @template.update_column(:subscription_id, 'sub-1')
    post :unpublish, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_response :success
    assert_not_includes response.body, "'smart'city'"
    assert_includes response.body, "smart\\'city"
  end

  # #35: the browser unpublish flow must only clear the local subscription id
  # when the broker actually removed the subscription. The clear
  # (clearSubscriptionId) must be gated behind a broker-success check, not run
  # unconditionally, and a broker failure must notify the user.
  def test_unpublish_clears_locally_only_on_broker_success
    @template.update_column(:subscription_id, 'sub-1')
    post :unpublish, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_response :success
    body = response.body

    # The clear is defined once and gated behind a broker-success check.
    assert_includes body, 'function clearSubscriptionId()'
    assert_includes body, 'if (response.ok || response.status === 404)'
    # It is invoked exactly once (inside the success guard), never
    # unconditionally in the failure or catch branches.
    assert_equal 1, body.scan(/return clearSubscriptionId\(\);/).length
    # Both the HTTP-failure branch and the network-error catch warn the user
    # that the subscription is still active (the rendered en warning text).
    assert_equal 2, body.scan(/could not be removed from the/).length
  end

  def test_copy_escapes_the_json_payload
    get :copy, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_response :success
    assert_not_includes response.body, INJECTION
    assert_includes response.body, ESCAPED_INJECTION
  end

  # Publishing an NGSI-LD template builds the LD subscription (#63): the broker
  # URL uses the /ngsi-ld/v1/ prefix and the payload carries the LD shape
  # (@context, notification.endpoint.receiverInfo, notificationTrigger).
  def test_publish_builds_an_ngsi_ld_subscription
    ld_connection = BrokerConnection.create!(
      name: 'LD broker',
      standard: 'NGSI-LD',
      url: 'https://broker.example.com',
      auth_mode: 'browser'
    )
    ld_template = SubscriptionTemplate.create!(
      broker_connection_id: ld_connection.id,
      status: 'active',
      name: 'LD alerts',
      subject: 'Sensor ${id}',
      description: 'A monitored value changed',
      context: 'https://uri.etsi.org/ngsi-ld/v1/ngsi-ld-core-context.jsonld',
      entities_string: '[{"idPattern": ".*", "type": "TemperatureSensor"}]',
      project_id: 1,
      tracker_id: 1,
      issue_status_id: 1,
      issue_priority_id: IssuePriority.first.id,
      member_id: 1
    )
    post :publish, params: { project_id: @project.id, id: ld_template.id }, xhr: true, format: :js
    assert_response :success
    assert_includes response.body, 'https://broker.example.com/ngsi-ld/v1/subscriptions'
    assert_includes response.body, 'receiverInfo'
    assert_includes response.body, 'notificationTrigger'
    assert_includes response.body, '@context'
    # The webhook secret rides in receiverInfo, and no NGSIv2 httpCustom shape.
    assert_includes response.body, ld_template.reload.webhook_secret
    assert_not_includes response.body, 'httpCustom'
    # LD subscriptions embed @context, so they are declared as JSON-LD.
    assert_includes response.body, 'application/ld+json'
  end

  # A stored-auth connection publishes server-side (#67): the encrypted token
  # is used as a Bearer header on the server and never reaches the browser.
  def test_publish_with_stored_auth_runs_server_side_and_hides_the_token
    stored_connection = BrokerConnection.create!(
      name: 'Stored broker',
      standard: 'NGSIv2',
      url: 'https://broker.example.com',
      auth_mode: 'stored',
      auth_token: 'server-secret-token'
    )
    @template.update_column(:broker_connection_id, stored_connection.id)

    captured_request = nil
    response_stub = Net::HTTPCreated.new('1.1', '201', 'Created')
    response_stub['Location'] = '/v2/subscriptions/sub-777'
    Net::HTTP.any_instance.stubs(:request).with { |req| captured_request = req }.returns(response_stub)

    post :publish, params: { project_id: @project.id, id: @template.id }, xhr: true
    assert_response :success

    assert_not_nil captured_request, 'the broker call must run server-side'
    assert_equal 'Bearer server-secret-token', captured_request['Authorization']
    # The token must never be rendered into the response for the browser.
    assert_not_includes response.body, 'server-secret-token'
    assert_equal 'sub-777', @template.reload.subscription_id
  end

  # --- form redesign (#66) ---------------------------------------------------

  # The new-template form renders the happy path plus three collapsed sections
  # and prefills defaults so the template is publishable without opening them.
  def test_new_renders_progressive_disclosure_form_with_defaults
    get :new, params: { project_id: @project.id }
    assert_response :success
    assert_select 'fieldset#gtt-fiware-section-filters.collapsible.collapsed'
    assert_select 'fieldset#gtt-fiware-section-issue_details.collapsible.collapsed'
    assert_select 'fieldset#gtt-fiware-section-subscription_options.collapsible.collapsed'
    assert_select 'select#gtt-fiware-connection-select option[data-standard=?]', 'NGSIv2'
    assert_select 'input[name=?][value=?]', 'subscription_template[subject]', '${type} ${id}'
    assert_select 'textarea[name=?]', 'subscription_template[description]', text: /changed/
    assert_select 'input[name=?]', 'publish_after_create'
  end

  # Sections with stored values are expanded on edit so nothing is hidden.
  def test_edit_expands_sections_that_contain_values
    @template.update_column(:expression_query, 'temperature>30')
    get :edit, params: { project_id: @project.id, id: @template.id }
    assert_response :success
    assert_select 'fieldset#gtt-fiware-section-filters.collapsible:not(.collapsed)'
    assert_select 'fieldset#gtt-fiware-section-issue_details.collapsible:not(.collapsed)'
    assert_select 'fieldset#gtt-fiware-section-subscription_options.collapsible.collapsed'
  end

  def create_params(overrides = {})
    {
      project_id: @project.id,
      subscription_template: {
        broker_connection_id: @broker_connection.id,
        status: 'active',
        name: 'Created via form',
        subject: '${type} ${id}',
        description: 'Entity ${id} changed.',
        entities_string: '[{"idPattern": ".*", "type": "TemperatureSensor"}]',
        tracker_id: 1,
        issue_status_id: 1,
        issue_priority_id: IssuePriority.first.id,
        member_id: 1
      }.merge(overrides)
    }
  end

  def test_create_saves_a_template
    assert_difference 'SubscriptionTemplate.count', 1 do
      post :create, params: create_params
    end
    assert_redirected_to settings_project_path(@project, tab: 'subscription_templates')
    assert_equal 'Created via form', SubscriptionTemplate.order(id: :desc).first.name
  end

  # Create-and-publish (#66): with a stored-auth connection the subscription is
  # published server-side right after the create.
  def test_create_and_publish_publishes_with_a_stored_connection
    stored_connection = BrokerConnection.create!(
      name: 'Stored create broker', standard: 'NGSIv2', url: 'https://broker.example.com',
      auth_mode: 'stored', auth_token: 'create-secret'
    )
    response_stub = Net::HTTPCreated.new('1.1', '201', 'Created')
    response_stub['Location'] = '/v2/subscriptions/sub-created-1'
    Net::HTTP.any_instance.stubs(:request).returns(response_stub)

    assert_difference 'SubscriptionTemplate.count', 1 do
      post :create, params: create_params(broker_connection_id: stored_connection.id).merge(publish_after_create: '1')
    end
    template = SubscriptionTemplate.order(id: :desc).first
    assert_equal 'sub-created-1', template.subscription_id
    assert_equal I18n.t(:subscription_published), flash[:notice]
  end

  # The form hides the button for browser-mode connections; a direct POST with
  # the flag must not attempt a broker call.
  def test_create_and_publish_refuses_a_browser_mode_connection
    assert_difference 'SubscriptionTemplate.count', 1 do
      post :create, params: create_params.merge(publish_after_create: '1')
    end
    template = SubscriptionTemplate.order(id: :desc).first
    assert_nil template.subscription_id
    assert_equal I18n.t(:subscription_unauthorized_error), flash[:error]
  end

  # --- live preview (#68) ----------------------------------------------------

  def preview_params(overrides = {})
    {
      project_id: @project.id,
      broker_connection_id: @broker_connection.id,
      entity_type: 'TemperatureSensor',
      subject: 'Sensor ${id}',
      description: 'Temperature is ${attrs.temperature.value}',
      notes: ''
    }.merge(overrides)
  end

  def stub_entities_response(payload)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns(payload.to_json)
    Net::HTTP.any_instance.stubs(:request).returns(response)
  end

  # The preview renders through the same pipeline notifications use, so it
  # shows exactly what a notification would produce.
  def test_preview_renders_templates_against_a_sample_entity
    stub_entities_response([
      { 'id' => 'urn:ngsi-ld:TemperatureSensor:001', 'type' => 'TemperatureSensor',
        'temperature' => { 'type' => 'Number', 'value' => 30 },
        'location' => { 'type' => 'geo:json', 'value' => { 'type' => 'Point', 'coordinates' => [135, 35] } } }
    ])
    post :preview, params: preview_params
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 'Sensor urn:ngsi-ld:TemperatureSensor:001', json['subject']
    assert_equal 'Temperature is 30', json['description']
    assert_nil json['notes']
    assert_equal 'urn:ngsi-ld:TemperatureSensor:001', json['entity_id']
    assert json['has_geometry']
  end

  def test_preview_reports_when_no_entity_matches
    stub_entities_response([])
    post :preview, params: preview_params
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)['error'], 'TemperatureSensor'
  end

  def test_preview_reports_broker_errors
    Net::HTTP.any_instance.stubs(:request).returns(Net::HTTPUnauthorized.new('1.1', '401', 'Unauthorized'))
    post :preview, params: preview_params
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)['error'], '401'
  end

  def test_preview_requires_a_connection_and_an_entity_type
    post :preview, params: preview_params(broker_connection_id: 987_654)
    assert_response :unprocessable_entity

    post :preview, params: preview_params(entity_type: '')
    assert_response :unprocessable_entity
  end

  def test_preview_uses_the_stored_token
    stored_connection = BrokerConnection.create!(
      name: 'Preview broker', standard: 'NGSIv2', url: 'https://broker.example.com',
      auth_mode: 'stored', auth_token: 'preview-secret'
    )
    captured_request = nil
    broker_response = Net::HTTPOK.new('1.1', '200', 'OK')
    broker_response.stubs(:body).returns([{ 'id' => 'x', 'type' => 'T' }].to_json)
    Net::HTTP.any_instance.stubs(:request).with { |req| captured_request = req }.returns(broker_response)

    post :preview, params: preview_params(broker_connection_id: stored_connection.id)
    assert_response :success
    assert_equal 'Bearer preview-secret', captured_request['Authorization']
    # The controller response (not the stubbed broker body) must not leak the token.
    assert_not_includes @response.body, 'preview-secret'
  end

  # --- sync (#13) -----------------------------------------------------------

  def stub_broker_get(response)
    Net::HTTP.any_instance.stubs(:request).returns(response)
  end

  def broker_json_response(body)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns(body.to_json)
    response
  end

  # The subscription is gone on the broker (e.g. a oneshot fired): sync clears
  # the stored subscription id so the template shows as unpublished again.
  def test_sync_clears_the_subscription_id_when_the_broker_returns_404
    @template.update_column(:subscription_id, 'sub-1')
    stub_broker_get(Net::HTTPNotFound.new('1.1', '404', 'Not Found'))

    post :sync, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_response :success
    assert_nil @template.reload.subscription_id
  end

  def test_sync_updates_the_local_status_from_the_broker
    @template.update_columns(subscription_id: 'sub-1', status: 'active')
    stub_broker_get(broker_json_response('status' => 'inactive'))

    post :sync, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_response :success
    assert_equal 'inactive', @template.reload.status
  end

  # NGSIv2 'failed' means the last notification failed but the subscription is
  # still active; 'expired' means it is no longer firing.
  def test_sync_maps_broker_statuses
    @template.update_columns(subscription_id: 'sub-1', status: 'inactive')
    stub_broker_get(broker_json_response('status' => 'failed'))
    post :sync, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_equal 'active', @template.reload.status

    stub_broker_get(broker_json_response('status' => 'expired'))
    post :sync, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_equal 'inactive', @template.reload.status
  end

  # An NGSI-LD broker without a status field reports isActive.
  def test_sync_uses_is_active_for_ngsi_ld
    ld_connection = BrokerConnection.create!(
      name: 'LD sync broker', standard: 'NGSI-LD', url: 'https://broker.example.com',
      context: 'https://broker.example.com/ctx.jsonld', auth_mode: 'browser'
    )
    @template.update_columns(broker_connection_id: ld_connection.id, subscription_id: 'urn:sub:1', status: 'active')
    stub_broker_get(broker_json_response('isActive' => false))

    post :sync, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_equal 'inactive', @template.reload.status
  end

  # A 200 whose status the plugin cannot interpret must be reported as an
  # error, not a successful sync.
  def test_sync_reports_an_error_for_an_unrecognized_status
    @template.update_columns(subscription_id: 'sub-1', status: 'active')
    stub_broker_get(broker_json_response('status' => 'hibernating'))

    post :sync, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_response :success
    assert_equal 'active', @template.reload.status
    assert_includes response.body, 'Could not query the broker'
  end

  def test_sync_keeps_state_and_reports_an_error_when_the_broker_fails
    @template.update_columns(subscription_id: 'sub-1', status: 'active')
    stub_broker_get(Net::HTTPUnauthorized.new('1.1', '401', 'Unauthorized'))

    post :sync, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_response :success
    assert_equal 'sub-1', @template.reload.subscription_id
    assert_equal 'active', @template.status
    assert_includes response.body, 'Could not query the broker'
  end

  def test_sync_uses_the_stored_token_server_side
    stored_connection = BrokerConnection.create!(
      name: 'Stored sync broker', standard: 'NGSIv2', url: 'https://broker.example.com',
      auth_mode: 'stored', auth_token: 'sync-secret'
    )
    @template.update_columns(broker_connection_id: stored_connection.id, subscription_id: 'sub-1')

    captured_request = nil
    response = broker_json_response('status' => 'active')
    Net::HTTP.any_instance.stubs(:request).with { |req| captured_request = req }.returns(response)

    post :sync, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_response :success
    assert_equal 'Bearer sync-secret', captured_request['Authorization']
    assert_not_includes response.body, 'sync-secret'
  end

  # State-changing endpoints must not be reachable via GET.
  def test_publish_unpublish_and_sync_are_post_only
    %w[publish unpublish sync].each do |action|
      assert_routing(
        { method: 'post', path: "/projects/#{@project.id}/subscription_templates/#{@template.id}/#{action}" },
        { controller: 'subscription_templates', action: action, project_id: @project.id.to_s, id: @template.id.to_s }
      )
      assert_raises(ActionController::RoutingError, "#{action} must not be reachable via GET") do
        Rails.application.routes.recognize_path(
          "/projects/#{@project.id}/subscription_templates/#{@template.id}/#{action}", method: :get
        )
      end
    end
  end

  def test_registration_callback_is_post_only
    assert_routing(
      { method: 'post', path: "/fiware/subscription_template/#{@template.id}/registration/sub-42" },
      { controller: 'subscription_templates', action: 'set_subscription_id',
        subscription_template_id: @template.id.to_s, subscription_id: 'sub-42', format: 'json' }
    )
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path(
        "/fiware/subscription_template/#{@template.id}/registration/sub-42", method: :get
      )
    end
  end

  # The registration callback stores the broker-assigned subscription id.
  # It is API-key authenticated (no browser session / CSRF token), so a POST
  # from tooling must be accepted and must persist the id.
  def test_set_subscription_id_via_post_updates_the_template
    @request.session[:user_id] = nil
    jsmith = User.find(2)
    with_settings rest_api_enabled: '1' do
      post :set_subscription_id, params: {
        subscription_template_id: @template.id, subscription_id: 'urn:sub:123',
        key: jsmith.api_key, format: :json
      }
    end
    assert_response :success
    assert_equal 'urn:sub:123', @template.reload.subscription_id
  end
end
