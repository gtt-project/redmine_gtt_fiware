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
    get :publish, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_response :success
    assert_not_includes response.body, INJECTION
    assert_includes response.body, ESCAPED_INJECTION
  end

  def test_publish_escapes_the_fiware_service_header
    get :publish, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
    assert_response :success
    assert_not_includes response.body, "'smart'city'"
    assert_includes response.body, "smart\\'city"
  end

  def test_unpublish_escapes_the_fiware_service_header
    @template.update_column(:subscription_id, 'sub-1')
    get :unpublish, params: { project_id: @project.id, id: @template.id }, xhr: true, format: :js
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
end
