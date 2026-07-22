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

    @template = SubscriptionTemplate.create!(
      standard: 'NGSIv2',
      status: 'active',
      name: 'Escaping test',
      broker_url: 'https://broker.example.com',
      subject: 'Sensor ${id}',
      description: 'A monitored value changed',
      notes: 'Latest reading: ${attrs.temperature.value}',
      fiware_service: "smart'city",
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
    ld_template = SubscriptionTemplate.create!(
      standard: 'NGSI-LD',
      status: 'active',
      name: 'LD alerts',
      broker_url: 'https://broker.example.com',
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
  end

  # State-changing endpoints must not be reachable via GET.
  def test_publish_and_unpublish_are_post_only
    assert_routing(
      { method: 'post', path: "/projects/#{@project.id}/subscription_templates/#{@template.id}/publish" },
      { controller: 'subscription_templates', action: 'publish', project_id: @project.id.to_s, id: @template.id.to_s }
    )
    assert_routing(
      { method: 'post', path: "/projects/#{@project.id}/subscription_templates/#{@template.id}/unpublish" },
      { controller: 'subscription_templates', action: 'unpublish', project_id: @project.id.to_s, id: @template.id.to_s }
    )
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path(
        "/projects/#{@project.id}/subscription_templates/#{@template.id}/publish", method: :get
      )
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
