require File.expand_path('../../test_helper', __FILE__)

class SubscriptionIssuesControllerTest < ActionController::TestCase
  fixtures :projects, :trackers, :projects_trackers, :issue_statuses,
           :users, :email_addresses, :members, :member_roles, :roles,
           :enumerations, :issues, :journals

  SECRET_HEADER = 'X-Gtt-Webhook-Secret'.freeze

  def setup
    @broker_connection = BrokerConnection.create!(
      name: 'Test broker',
      standard: 'NGSIv2',
      url: 'https://broker.example.com',
      auth_mode: 'browser'
    )
    @template = SubscriptionTemplate.create!(
      broker_connection_id: @broker_connection.id,
      status: 'active',
      name: 'Temperature alerts',
      # Since #64 the broker POSTs raw entities and the plugin renders these
      # ${...} expressions itself (see NotificationProcessor / TemplateRenderer).
      subject: 'Sensor ${id}',
      description: 'Temperature is ${attrs.temperature.value}',
      notes: 'Latest reading: ${attrs.temperature.value}',
      threshold_create: 3600,
      entities_string: '[{"idPattern": ".*", "type": "TemperatureSensor"}]',
      project_id: 1,
      tracker_id: 1,
      issue_status_id: 1,
      issue_priority_id: IssuePriority.first.id,
      member_id: 1 # jsmith on project 1 (Manager)
    )
  end

  # One raw NGSIv2 entity as the broker sends it inside the notification's
  # data[] array.
  def entity(overrides = {})
    {
      'id' => 'urn:ngsi-ld:TemperatureSensor:001',
      'type' => 'TemperatureSensor',
      'temperature' => { 'type' => 'Number', 'value' => 30 }
    }.merge(overrides)
  end

  # Posts a broker notification (entities under `data`) with the webhook secret
  # in the request header and a raw JSON body, as the broker does.
  def post_notification(entities: [entity], template_id: @template.id, secret: @template.webhook_secret)
    @request.headers[SECRET_HEADER] = secret unless secret.nil?
    @request.headers['CONTENT_TYPE'] = 'application/json'
    post :create, params: { subscription_template_id: template_id }, body: { data: entities }.to_json
  end

  # The notification route must carry format: 'json'. That is what makes
  # Redmine treat it as an api_request? and exempt it from the CSRF token check
  # (core's verify_authenticity_token), instead of the controller skipping
  # forgery protection itself. Forgery protection is disabled in the test
  # environment, so only this routing assertion pins the production behaviour.
  def test_notification_route_is_a_json_api_endpoint
    assert_routing(
      { method: 'post', path: "/fiware/subscription_template/#{@template.id}/notification" },
      { controller: 'subscription_issues', action: 'create',
        subscription_template_id: @template.id.to_s, format: 'json' }
    )
  end

  def test_create_rejects_a_missing_secret
    assert_no_difference 'Issue.count' do
      post_notification(secret: nil)
    end
    assert_response :unauthorized
  end

  def test_create_rejects_a_wrong_secret
    assert_no_difference 'Issue.count' do
      post_notification(secret: 'not-the-secret')
    end
    assert_response :unauthorized
  end

  # A missing template returns the same 401 as a wrong secret, so the endpoint
  # never reveals whether a given template id exists.
  def test_create_does_not_leak_template_existence
    post_notification(template_id: 987_654, secret: 'anything')
    assert_response :unauthorized
    missing_body = @response.body

    post_notification(secret: 'wrong-secret')
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
    assert_equal 'Temperature is 30', issue.description
    assert_equal 'urn:ngsi-ld:TemperatureSensor:001', issue.fiware_entity
    assert_equal @template.id, issue.subscription_template_id
    assert_equal @template.member.user_id, issue.author_id
  end

  # Echo suppression (#69): an issue created from a broker notification must
  # not be emitted back to a broker, even when the project and tracker have an
  # emission mapping - a subscription plus an emission on the same tenant
  # would loop otherwise.
  def test_notification_created_issues_are_not_emitted_back
    project = Project.find(1)
    project.enabled_module_names = project.enabled_module_names | ['gtt_fiware_emission']
    ld_connection = BrokerConnection.create!(
      name: 'Echo broker', standard: 'NGSI-LD',
      url: 'https://broker.example.com', auth_mode: 'stored'
    )
    EmissionMapping.create!(broker_connection: ld_connection, tracker: Tracker.find(1), subtype: 'WorkOrder')

    Net::HTTP.any_instance.expects(:request).never
    with_settings plugin_redmine_gtt_fiware: { 'fiware_instance_id' => 'test-town' } do
      assert_difference 'Issue.count', 1 do
        post_notification
      end
    end
    assert_response :success
  end

  # --- federation awareness (#70, 4a) ----------------------------------------

  def sibling(status: 'open')
    RedmineGttFiware::FederationSiblings::Sibling.new(
      urn: 'urn:ngsi-ld:Issue:redmine:nexco-east:7', org: 'nexco-east',
      subtype: 'WorkOrder', status: status, status_label: 'In Progress',
      title: 'Container full', source: 'https://other.example/issues/7'
    )
  end

  def test_annotate_policy_notes_siblings_on_the_new_issue
    @template.update_column(:federation_policy, 'annotate')
    RedmineGttFiware::FederationSiblings.any_instance.stubs(:for_entity).returns([sibling])

    assert_difference 'Issue.count', 1 do
      post_notification
    end
    assert_response :success
    issue = Issue.order(id: :desc).first
    note = issue.journals.last.notes
    assert_includes note, 'nexco-east'
    assert_includes note, 'https://other.example/issues/7'
  end

  # Suppression is deliberate, successful handling: a batch of only
  # suppressed entities must be a 200, or the broker retries forever.
  def test_suppress_policy_skips_creation_and_answers_200
    @template.update_column(:federation_policy, 'suppress')
    RedmineGttFiware::FederationSiblings.any_instance.stubs(:for_entity).returns([sibling])

    assert_no_difference 'Issue.count' do
      post_notification
    end
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body['suppressed']
    assert_equal 0, body['created']
  end

  def test_suppress_policy_creates_when_all_siblings_are_closed
    @template.update_column(:federation_policy, 'suppress')
    RedmineGttFiware::FederationSiblings.any_instance.stubs(:for_entity).returns([sibling(status: 'closed')])

    assert_difference 'Issue.count', 1 do
      post_notification
    end
    assert_response :success
  end

  def test_off_policy_never_queries_the_broker
    RedmineGttFiware::FederationSiblings.any_instance.expects(:for_entity).never
    assert_difference 'Issue.count', 1 do
      post_notification
    end
    assert_response :success
  end

  # Two notifications for the same entity within the threshold_create window
  # update the first issue instead of creating a duplicate (#47).
  def test_create_updates_a_recent_issue_instead_of_duplicating
    post_notification
    assert_response :success
    issue = Issue.order(id: :desc).first

    assert_no_difference 'Issue.count' do
      post_notification(entities: [entity('temperature' => { 'type' => 'Number', 'value' => 42 })])
    end
    assert_response :success
    issue.reload
    assert_equal 'Latest reading: 42', issue.journals.order(:id).last.notes
  end

  # #47: value updates must be applied even when the template has no notes
  # configured. A geometry change within the threshold window updates the
  # issue's geom and records a journal detail, notes or not.
  def test_update_applies_geometry_change_without_notes_configured
    skip 'redmine_gtt not installed' unless Redmine::Plugin.installed?(:redmine_gtt)
    Project.find(1).enabled_module_names |= ['gtt']
    @template.update_columns(notes: nil, geometry: '${location}')

    location = { 'type' => 'geo:json', 'value' => { 'type' => 'Point', 'coordinates' => [135.0, 35.0] } }
    post_notification(entities: [entity('location' => location)])
    assert_response :success
    issue = Issue.order(id: :desc).first
    assert_not_nil issue.geom

    moved = { 'type' => 'geo:json', 'value' => { 'type' => 'Point', 'coordinates' => [136.0, 36.0] } }
    original_geom = issue.geom
    assert_no_difference 'Issue.count' do
      post_notification(entities: [entity('location' => moved)])
    end
    assert_response :success
    issue.reload
    assert_not_equal original_geom, issue.geom, 'the geometry must actually change'
    journal = issue.journals.order(:id).last
    assert_not_nil journal
    assert journal.notes.blank?, 'no notes template configured, so the journal has no notes'
    assert journal.details.any? { |d| d.prop_key == 'geom' },
           'geometry change must be recorded as a journal detail'
  end

  # #47: new attachments (e.g. new photos) are added on update even when the
  # template has no notes configured; already-attached filenames are skipped.
  def test_update_adds_new_attachments_without_notes_configured
    set_tmp_attachments_directory
    tempfile = Tempfile.new(['fetched', '.png'])
    tempfile.binmode
    tempfile.write('PNGDATA')
    tempfile.rewind
    result = RedmineGttFiware::AttachmentFetcher::Result.new(
      tempfile: tempfile, content_type: 'image/png'
    )
    RedmineGttFiware::AttachmentFetcher.stubs(:for_template).returns(FakeFetcher.new(result))
    @template.update_columns(
      notes: nil,
      attachments: [{ 'url' => 'https://broker.example.com/photo.png', 'filename' => 'reading-${attrs.temperature.value}.png' }]
    )

    post_notification
    assert_response :success
    issue = Issue.order(id: :desc).first
    assert_equal ['reading-30.png'], issue.attachments.map(&:filename)

    # Same filename again: skipped. New reading -> new filename: attached.
    assert_no_difference 'Issue.count' do
      post_notification(entities: [entity, entity('temperature' => { 'type' => 'Number', 'value' => 31 })])
    end
    assert_response :success
    issue.reload
    assert_equal ['reading-30.png', 'reading-31.png'], issue.attachments.map(&:filename).sort
    # No notes template configured: the update journals must carry no notes.
    assert issue.journals.all? { |j| j.notes.blank? },
           'no notes template configured, so update journals have no notes'
  ensure
    tempfile&.close!
  end

  # Outside the threshold_create window a new notification creates a new issue.
  def test_create_makes_a_new_issue_outside_the_threshold_window
    post_notification
    Issue.order(id: :desc).first.update_column(:created_on, 2.hours.ago)

    assert_difference 'Issue.count', 1 do
      post_notification
    end
    assert_response :success
  end

  # Every entity in a multi-entity notification is processed.
  def test_create_processes_every_entity_in_the_notification
    entities = [
      entity('id' => 'urn:ngsi-ld:TemperatureSensor:001'),
      entity('id' => 'urn:ngsi-ld:TemperatureSensor:002')
    ]
    assert_difference 'Issue.count', 2 do
      post_notification(entities: entities)
    end
    assert_response :success
    fiware_entities = Issue.order(id: :desc).limit(2).map(&:fiware_entity)
    assert_includes fiware_entities, 'urn:ngsi-ld:TemperatureSensor:001'
    assert_includes fiware_entities, 'urn:ngsi-ld:TemperatureSensor:002'
  end

  def test_create_rejects_a_notification_without_entities
    assert_no_difference 'Issue.count' do
      post_notification(entities: [])
    end
    assert_response :unprocessable_entity
  end

  # A malformed body is a 400 (bad request), distinct from a well-formed
  # notification that simply carries no entities (422). Sent without a JSON
  # content type so the controller's own parse (not Rails' params middleware,
  # which would 400 in the middleware layer) handles it.
  def test_create_rejects_a_malformed_json_body
    @request.headers[SECRET_HEADER] = @template.webhook_secret
    @request.headers['CONTENT_TYPE'] = 'text/plain'
    assert_no_difference 'Issue.count' do
      post :create, params: { subscription_template_id: @template.id }, body: '{ not json'
    end
    assert_response :bad_request
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

  # Attachments are configured on the template (not carried in the notification)
  # and rendered/fetched plugin-side. The SSRF protections in AttachmentFetcher
  # still apply on every download.
  def test_create_skips_attachments_with_non_https_urls
    @template.update_column(:attachments, [{ 'url' => 'http://169.254.169.254/latest/meta-data', 'filename' => 'meta.txt' }])
    assert_difference 'Issue.count', 1 do
      post_notification
    end
    assert_response :success
    assert_equal 0, Issue.order(id: :desc).first.attachments.count
  end

  def test_create_skips_attachments_from_hosts_not_on_the_allowlist
    @template.update_column(:attachments, [{ 'url' => 'https://evil.example.org/file.png', 'filename' => 'file.png' }])
    assert_difference 'Issue.count', 1 do
      post_notification
    end
    assert_response :success
    assert_equal 0, Issue.order(id: :desc).first.attachments.count
  end

  def test_create_skips_attachments_resolving_to_non_public_addresses
    @broker_connection.update_column(:url, 'https://localhost')
    @template.update_column(:attachments, [{ 'url' => 'https://localhost/file.png', 'filename' => 'file.png' }])
    assert_difference 'Issue.count', 1 do
      post_notification
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

  def test_create_attaches_allowed_attachments_and_renders_their_templates
    set_tmp_attachments_directory
    tempfile = Tempfile.new(['fetched', '.png'])
    tempfile.binmode
    tempfile.write('PNGDATA')
    tempfile.rewind
    result = RedmineGttFiware::AttachmentFetcher::Result.new(
      tempfile: tempfile, content_type: 'image/png'
    )
    RedmineGttFiware::AttachmentFetcher.stubs(:for_template).returns(FakeFetcher.new(result))
    # The filename is templated against the entity to prove plugin-side rendering.
    @template.update_column(:attachments, [{ 'url' => 'https://broker.example.com/photo.png', 'filename' => 'reading-${attrs.temperature.value}.png' }])

    assert_difference 'Issue.count', 1 do
      post_notification
    end
    assert_response :success
    issue = Issue.order(id: :desc).first
    assert_equal 1, issue.attachments.count
    assert_equal 'reading-30.png', issue.attachments.first.filename
    assert_equal 'image/png', issue.attachments.first.content_type
  ensure
    tempfile&.close!
  end
end
