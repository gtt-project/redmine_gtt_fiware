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
      subject: "Sensor #{INJECTION}",
      description: "Desc #{INJECTION}",
      notes: "Note #{INJECTION}",
      fiware_service: "smart'city",
      entities_string: '[{"idPattern": ".*", "type": "TemperatureSensor"}]',
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

  def test_copy_escapes_the_json_payload
    get :copy, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_response :success
    assert_not_includes response.body, INJECTION
    assert_includes response.body, ESCAPED_INJECTION
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
