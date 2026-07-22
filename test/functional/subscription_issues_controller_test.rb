require File.expand_path('../../test_helper', __FILE__)

class SubscriptionIssuesControllerTest < ActionController::TestCase
  fixtures :projects, :trackers, :projects_trackers, :issue_statuses,
           :users, :email_addresses, :members, :member_roles, :roles,
           :enumerations, :issues, :journals

  def setup
    @template = SubscriptionTemplate.create!(
      standard: 'NGSIv2',
      status: 'active',
      name: 'Temperature alerts',
      broker_url: 'https://broker.example.com',
      subject: 'Sensor ${id}',
      description: 'A monitored value changed',
      entities_string: '[{"idPattern": ".*", "type": "TemperatureSensor"}]',
      project_id: 1,
      tracker_id: 1,
      issue_status_id: 1,
      issue_priority_id: IssuePriority.first.id,
      member_id: 1
    )
    @request.session[:user_id] = 2 # jsmith, manager of project 1
  end

  def notification_params(overrides = {})
    {
      subscription_template_id: @template.id,
      subject: 'Sensor urn:ngsi-ld:TemperatureSensor:001',
      description: 'Temperature above threshold',
      entity: 'urn:ngsi-ld:TemperatureSensor:001',
    }.merge(overrides)
  end

  def test_create_returns_404_for_unknown_template
    post :create, params: notification_params(subscription_template_id: 987654)
    assert_response :not_found
  end

  def test_create_requires_add_issues_permission
    @request.session[:user_id] = nil
    # Builtin roles may grant add_issues on public projects; strip it so
    # the anonymous request is unauthorized regardless of fixture details.
    Role.all.each { |role| role.remove_permission!(:add_issues) }
    assert_no_difference 'Issue.count' do
      post :create, params: notification_params
    end
    assert_response :forbidden
  end

  def test_create_creates_an_issue
    assert_difference 'Issue.count', 1 do
      post :create, params: notification_params
    end
    assert_response :success
    issue = Issue.order(id: :desc).first
    assert_equal 'Sensor urn:ngsi-ld:TemperatureSensor:001', issue.subject
    assert_equal 'urn:ngsi-ld:TemperatureSensor:001', issue.fiware_entity
    assert_equal @template.id, issue.subscription_template_id
    assert_equal @template.project, issue.project
  end

  def test_create_skips_attachments_with_non_https_urls
    assert_difference 'Issue.count', 1 do
      post :create, params: notification_params(
        attachments: [{ url: 'http://169.254.169.254/latest/meta-data', filename: 'meta.txt' }]
      )
    end
    assert_response :success
    assert_equal 0, Issue.order(id: :desc).first.attachments.count
  end

  def test_create_skips_attachments_from_hosts_not_on_the_allowlist
    assert_difference 'Issue.count', 1 do
      post :create, params: notification_params(
        attachments: [{ url: 'https://evil.example.org/file.png', filename: 'file.png' }]
      )
    end
    assert_response :success
    assert_equal 0, Issue.order(id: :desc).first.attachments.count
  end

  def test_create_skips_attachments_resolving_to_non_public_addresses
    # localhost is allowlisted via the broker URL here, but resolves to a
    # loopback address, so the download must still be rejected.
    @template.update_column(:broker_url, 'https://localhost')
    assert_difference 'Issue.count', 1 do
      post :create, params: notification_params(
        attachments: [{ url: 'https://localhost/file.png', filename: 'file.png' }]
      )
    end
    assert_response :success
    assert_equal 0, Issue.order(id: :desc).first.attachments.count
  end

  def test_create_attaches_allowed_attachments
    set_tmp_attachments_directory
    tempfile = Tempfile.new(['fetched', '.png'])
    tempfile.binmode
    tempfile.write('PNGDATA')
    tempfile.rewind
    result = RedmineGttFiware::AttachmentFetcher::Result.new(
      tempfile: tempfile, content_type: 'image/png'
    )
    RedmineGttFiware::AttachmentFetcher.any_instance.stubs(:fetch).returns(result)

    assert_difference 'Issue.count', 1 do
      post :create, params: notification_params(
        attachments: [{ url: 'https://broker.example.com/photo.png', filename: 'photo.png' }]
      )
    end
    assert_response :success
    issue = Issue.order(id: :desc).first
    assert_equal 1, issue.attachments.count
    attachment = issue.attachments.first
    assert_equal 'photo.png', attachment.filename
    assert_equal 'image/png', attachment.content_type
  ensure
    tempfile&.close!
  end
end
