require File.expand_path('../../test_helper', __FILE__)

# End-to-end guardrails for issue emission (#69, step 1): the after_commit
# hooks, the guard chain (instance id, project opt-in, privacy, echo
# suppression) and the broker HTTP conversation, with Net::HTTP stubbed.
class EmitterTest < ActiveSupport::TestCase
  fixtures :projects, :trackers, :projects_trackers, :issue_statuses,
           :users, :email_addresses, :members, :member_roles, :roles,
           :enumerations, :issues

  EMISSION_SETTINGS = { 'fiware_instance_id' => 'test-town' }.freeze

  def setup
    @project = Project.find(1)
    @project.enabled_module_names = @project.enabled_module_names | ['gtt_fiware_emission']
    @connection = BrokerConnection.create!(
      name: 'Emitting broker', standard: 'NGSI-LD',
      url: 'https://broker.example.com', fiware_service: 'testtown',
      auth_mode: 'stored', auth_token: 'emit-token', token_header: 'X-Api-Key'
    )
    EmissionMapping.create!(broker_connection: @connection, tracker: Tracker.find(1), subtype: 'WorkOrder')
  end

  def build_issue(attributes = {})
    Issue.new({
      project_id: @project.id, tracker_id: 1, status_id: 1,
      priority: IssuePriority.first, author_id: 2,
      subject: 'Emitted issue'
    }.merge(attributes))
  end

  def stub_broker(response)
    requests = []
    Net::HTTP.any_instance.stubs(:request).with { |req| requests << req; true }.returns(response)
    requests
  end

  def created_response
    Net::HTTPCreated.new('1.1', '201', 'Created')
  end

  def test_issue_create_emits_an_upsert_with_auth_and_tenant
    requests = stub_broker(created_response)
    issue = nil
    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      issue = build_issue
      issue.save!
    end

    post = requests.find { |r| r.is_a?(Net::HTTP::Post) }
    assert_not_nil post, 'issue creation must POST an entity'
    assert_equal '/ngsi-ld/v1/entities', post.path
    assert_equal 'application/ld+json', post['Content-Type']
    assert_equal 'emit-token', post['X-Api-Key']
    assert_equal 'testtown', post['NGSILD-Tenant']
    body = JSON.parse(post.body)
    assert_equal "urn:ngsi-ld:Issue:redmine:test-town:#{issue.id}", body['id']
    assert_equal 'WorkOrder', body.dig('subtype', 'value')
  end

  # 409 means the entity exists: update its attributes, without the immutable
  # id/type in the PATCH body.
  def test_conflict_falls_back_to_a_patch
    conflict = Net::HTTPConflict.new('1.1', '409', 'Conflict')
    requests = []
    responses = [conflict, Net::HTTPNoContent.new('1.1', '204', 'No Content')]
    Net::HTTP.any_instance.stubs(:request).with { |req| requests << req; true }
             .returns(*responses)

    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      build_issue.save!
    end

    patch = requests.find { |r| r.is_a?(Net::HTTP::Patch) }
    assert_not_nil patch, '409 must be followed by a PATCH'
    assert_match %r{/ngsi-ld/v1/entities/urn:ngsi-ld:Issue:redmine:test-town:\d+/attrs\z}, patch.path
    body = JSON.parse(patch.body)
    assert_nil body['id']
    assert_nil body['type']
    assert body.key?('status')
  end

  def test_issue_destroy_emits_a_delete
    requests = stub_broker(Net::HTTPNoContent.new('1.1', '204', 'No Content'))
    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      issue = build_issue
      issue.save!
      requests.clear
      issue.destroy
    end

    delete = requests.find { |r| r.is_a?(Net::HTTP::Delete) }
    assert_not_nil delete, 'issue destruction must DELETE the entity'
    assert_match %r{/ngsi-ld/v1/entities/urn:ngsi-ld:Issue:redmine:test-town:\d+\z}, delete.path
  end

  # --- the guard chain --------------------------------------------------------

  def test_no_emission_without_an_instance_id
    requests = stub_broker(created_response)
    with_settings plugin_redmine_gtt_fiware: { 'fiware_instance_id' => '' } do
      build_issue.save!
    end
    assert_empty requests
  end

  def test_no_emission_with_a_malformed_instance_id
    requests = stub_broker(created_response)
    with_settings plugin_redmine_gtt_fiware: { 'fiware_instance_id' => 'no spaces!' } do
      build_issue.save!
    end
    assert_empty requests
  end

  def test_no_emission_without_the_project_module
    @project.enabled_module_names = @project.enabled_module_names - ['gtt_fiware_emission']
    requests = stub_broker(created_response)
    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      build_issue.save!
    end
    assert_empty requests
  end

  def test_no_emission_for_private_issues
    requests = stub_broker(created_response)
    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      build_issue(is_private: true).save!
    end
    assert_empty requests
  end

  def test_no_emission_for_unmapped_trackers
    requests = stub_broker(created_response)
    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      build_issue(tracker_id: 2).save!
    end
    assert_empty requests
  end

  # Echo suppression: issues written under Emitter.suppress (the
  # NotificationProcessor path) must not be emitted back.
  def test_no_emission_while_suppressed
    requests = stub_broker(created_response)
    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      RedmineGttFiware::Emitter.suppress { build_issue.save! }
    end
    assert_empty requests
  end

  # Nested suppress blocks must not re-enable emission for the outer one.
  def test_suppress_nests_safely
    RedmineGttFiware::Emitter.suppress do
      RedmineGttFiware::Emitter.suppress {}
      assert RedmineGttFiware::Emitter.suppressed?, 'outer suppression must survive a nested block'
    end
    assert_not RedmineGttFiware::Emitter.suppressed?
  end

  # An unreachable broker must never block saving an issue.
  def test_broker_failure_never_raises
    Net::HTTP.any_instance.stubs(:request).raises(Errno::ECONNREFUSED)
    issue = nil
    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      assert_nothing_raised do
        issue = build_issue
        issue.save!
      end
    end
    assert issue.persisted?
  end

  def error_response
    response = Net::HTTPInternalServerError.new('1.1', '500', 'Internal Server Error')
    response.stubs(:body).returns('broker exploded')
    response
  end

  # A broker rejection is logged (including a body excerpt) and the save
  # still succeeds: log_failure must not itself raise on the response.
  def test_broker_error_response_is_logged_and_does_not_block_the_save
    stub_broker(error_response)
    issue = nil
    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      Rails.logger.expects(:error).with { |msg| msg.include?('answered 500') && msg.include?('broker exploded') }
      issue = build_issue
      issue.save!
    end
    assert issue.persisted?
  end

  # 409 -> PATCH fallback where the PATCH also fails: the failure of the
  # second request is the one reported.
  def test_conflict_then_failed_patch_is_logged
    conflict = Net::HTTPConflict.new('1.1', '409', 'Conflict')
    responses = [conflict, error_response]
    requests = []
    Net::HTTP.any_instance.stubs(:request).with { |req| requests << req; true }
             .returns(*responses)
    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      Rails.logger.expects(:error).with { |msg| msg.include?('answered 500') }
      build_issue.save!
    end
    assert requests.any? { |r| r.is_a?(Net::HTTP::Patch) }, 'the 409 must trigger the PATCH fallback'
  end

  # DELETE answering 404 means "never emitted or already gone": deliberately
  # not a failure, so nothing is logged.
  def test_delete_tolerates_a_404
    not_found = Net::HTTPNotFound.new('1.1', '404', 'Not Found')
    issue = nil
    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      stub_broker(created_response)
      issue = build_issue
      issue.save!
    end

    stub_broker(not_found)
    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      Rails.logger.expects(:error).never
      issue.destroy
    end
  end

  # One failing connection neither raises nor blocks the others.
  def test_a_failing_connection_does_not_block_the_next_one
    second = BrokerConnection.create!(
      name: 'Second broker', standard: 'NGSI-LD',
      url: 'https://other.example.com', auth_mode: 'stored'
    )
    EmissionMapping.create!(broker_connection: second, tracker: Tracker.find(1), subtype: 'WorkOrder')

    attempts = []
    # One stub: the matcher counts attempts and raises on the first, so the
    # first connection fails and the second is the one that must still run.
    Net::HTTP.any_instance.stubs(:request).with do |_req|
      attempts << 1
      raise Errno::ECONNREFUSED if attempts.length == 1

      true
    end.returns(created_response)

    issue = nil
    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      assert_nothing_raised do
        issue = build_issue
        issue.save!
      end
    end
    assert issue.persisted?
    assert_equal 2, attempts.length, 'the second connection must still be attempted'
  end
end
