require File.expand_path('../../test_helper', __FILE__)

class SubscriptionIssuesControllerTest < ActionController::TestCase
  fixtures :projects, :trackers, :projects_trackers, :issue_statuses,
           :users, :email_addresses, :members, :member_roles, :roles,
           :enumerations, :issues, :journals

  SECRET_HEADER = 'X-Gtt-Webhook-Secret'.freeze

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
      member_id: 1 # jsmith on project 1 (Manager)
    )
  end

  def notification_params(overrides = {})
    {
      subscription_template_id: @template.id,
      subject: 'Sensor urn:ngsi-ld:TemperatureSensor:001',
      description: 'Temperature above threshold',
      entity: 'urn:ngsi-ld:TemperatureSensor:001',
    }.merge(overrides)
  end

  # Posts a notification with the given webhook secret in the request header.
  def post_notification(params = notification_params, secret: @template.webhook_secret)
    @request.headers[SECRET_HEADER] = secret unless secret.nil?
    post :create, params: params
  end

  def test_create_rejects_a_missing_secret
    assert_no_difference 'Issue.count' do
      post_notification(notification_params, secret: nil)
    end
    assert_response :unauthorized
  end

  def test_create_rejects_a_wrong_secret
    assert_no_difference 'Issue.count' do
      post_notification(notification_params, secret: 'not-the-secret')
    end
    assert_response :unauthorized
  end

  # A missing template returns the same 401 as a wrong secret, so the endpoint
  # never reveals whether a given template id exists.
  def test_create_does_not_leak_template_existence
    post_notification(notification_params(subscription_template_id: 987_654), secret: 'anything')
    assert_response :unauthorized
    missing_body = @response.body

    post_notification(notification_params, secret: 'wrong-secret')
    assert_response :unauthorized
    assert_equal missing_body, @response.body
  end

  def test_create_creates_an_issue_and_authors_it_as_the_member
    assert_difference 'Issue.count', 1 do
      post_notification
    end
    assert_response :success
    issue = Issue.order(id: :desc).first
    assert_equal 'Sensor urn:ngsi-ld:TemperatureSensor:001', issue.subject
    assert_equal 'urn:ngsi-ld:TemperatureSensor:001', issue.fiware_entity
    assert_equal @template.id, issue.subscription_template_id
    assert_equal @template.member.user_id, issue.author_id
  end

  def test_create_rejects_when_the_member_cannot_add_issues
    Role.all.each { |role| role.remove_permission!(:add_issues) }
    assert_no_difference 'Issue.count' do
      post_notification
    end
    assert_response :forbidden
  end

  # A valid secret whose member's user no longer exists must yield a controlled
  # 403, not a 500 (#81 follow-up).
  def test_create_handles_a_member_without_a_user
    member = @template.member
    member.stubs(:user).returns(nil)
    # The controller loads its own template instance, so stub member there too.
    SubscriptionTemplate.any_instance.stubs(:member).returns(member)
    assert_no_difference 'Issue.count' do
      post_notification
    end
    assert_response :forbidden
  end

  def test_create_skips_attachments_with_non_https_urls
    assert_difference 'Issue.count', 1 do
      post_notification(notification_params(
        attachments: [{ url: 'http://169.254.169.254/latest/meta-data', filename: 'meta.txt' }]
      ))
    end
    assert_response :success
    assert_equal 0, Issue.order(id: :desc).first.attachments.count
  end

  def test_create_skips_attachments_from_hosts_not_on_the_allowlist
    assert_difference 'Issue.count', 1 do
      post_notification(notification_params(
        attachments: [{ url: 'https://evil.example.org/file.png', filename: 'file.png' }]
      ))
    end
    assert_response :success
    assert_equal 0, Issue.order(id: :desc).first.attachments.count
  end

  def test_create_skips_attachments_resolving_to_non_public_addresses
    @template.update_column(:broker_url, 'https://localhost')
    assert_difference 'Issue.count', 1 do
      post_notification(notification_params(
        attachments: [{ url: 'https://localhost/file.png', filename: 'file.png' }]
      ))
    end
    assert_response :success
    assert_equal 0, Issue.order(id: :desc).first.attachments.count
  end

  # Fake fetcher returning a canned result without any network access, stubbed
  # in via the AttachmentFetcher.for_template factory (Mocha, loaded by
  # Redmine's test harness).
  class FakeFetcher
    def initialize(result)
      @result = result
    end

    def fetch(_url)
      @result
    end
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
    RedmineGttFiware::AttachmentFetcher.stubs(:for_template).returns(FakeFetcher.new(result))

    assert_difference 'Issue.count', 1 do
      post_notification(notification_params(
        attachments: [{ url: 'https://broker.example.com/photo.png', filename: 'photo.png' }]
      ))
    end
    assert_response :success
    issue = Issue.order(id: :desc).first
    assert_equal 1, issue.attachments.count
    assert_equal 'photo.png', issue.attachments.first.filename
    assert_equal 'image/png', issue.attachments.first.content_type
  ensure
    tempfile&.close!
  end
end
