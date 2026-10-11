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
    # The id keeps the IssueUrn shape (ids never change); the type is the
    # redmine subject's Issue (datamodels.jp's Task IRI).
    assert_equal "urn:ngsi-ld:Issue:redmine:test-town:#{issue.id}", body['id']
    assert_equal 'Issue', body['type']
    assert_equal 'Emitted issue', body.dig('name', 'value')
    assert_equal 'WorkOrder', body.dig('subtype', 'value')
  end

  def remote_entity_response(extra_attributes = {})
    entity = {
      'id' => 'urn:ngsi-ld:Issue:redmine:test-town:1', 'type' => 'Issue',
      'name' => { 'type' => 'Property', 'value' => 'Emitted issue' },
      'createdAt' => '2026-08-01T00:00:00Z', 'modifiedAt' => '2026-08-01T00:00:00Z'
    }.merge(extra_attributes)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns(entity.to_json)
    response
  end

  def no_content_response
    Net::HTTPNoContent.new('1.1', '204', 'No Content')
  end

  # 409 means the entity exists: read it back, bring its attributes in line
  # via append (POST ../attrs, which unlike PATCH also lands attributes the
  # broker did not have yet), without the immutable id/type in the body.
  def test_conflict_falls_back_to_an_attribute_append
    conflict = Net::HTTPConflict.new('1.1', '409', 'Conflict')
    requests = []
    responses = [conflict, remote_entity_response, no_content_response]
    Net::HTTP.any_instance.stubs(:request).with { |req| requests << req; true }
             .returns(*responses)

    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      build_issue.save!
    end

    get = requests.find { |r| r.is_a?(Net::HTTP::Get) }
    assert_not_nil get, 'the 409 must trigger a read-back of the broker entity'
    append = requests.find { |r| r.is_a?(Net::HTTP::Post) && r.path.end_with?('/attrs') }
    assert_not_nil append, '409 must be followed by an attribute append'
    assert_match %r{/ngsi-ld/v1/entities/urn:ngsi-ld:Issue:redmine:test-town:\d+/attrs\z}, append.path
    body = JSON.parse(append.body)
    assert_nil body['id']
    assert_nil body['type']
    assert body.key?('progress')
    assert_not requests.any? { |r| r.is_a?(Net::HTTP::Delete) },
               'nothing was stale, so no attribute must be deleted'
  end

  # Attributes the broker still has but the current representation no longer
  # carries are removed with per-attribute DELETEs (#146).
  def test_conflict_deletes_stale_broker_attributes
    conflict = Net::HTTPConflict.new('1.1', '409', 'Conflict')
    remote = remote_entity_response(
      'assignee' => { 'type' => 'Property', 'value' => 'Former Assignee' },
      'refersTo' => { 'type' => 'Relationship', 'object' => 'urn:x:gone' }
    )
    requests = []
    responses = [conflict, remote, no_content_response, no_content_response, no_content_response]
    Net::HTTP.any_instance.stubs(:request).with { |req| requests << req; true }
             .returns(*responses)

    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      build_issue.save!
    end

    deletes = requests.select { |r| r.is_a?(Net::HTTP::Delete) }.map(&:path)
    assert_equal 2, deletes.length, 'each stale attribute must be deleted individually'
    assert deletes.any? { |path| path.end_with?('/attrs/assignee') }
    assert deletes.any? { |path| path.end_with?('/attrs/refersTo') }
    assert_not deletes.any? { |path| path.include?('/attrs/name') },
               'attributes the representation still carries must not be deleted'
  end

  # A stale attribute already gone on the broker (deleted concurrently) is
  # the desired state, not a failure.
  def test_stale_attribute_deletion_tolerates_a_404
    conflict = Net::HTTPConflict.new('1.1', '409', 'Conflict')
    remote = remote_entity_response('assignee' => { 'type' => 'Property', 'value' => 'x' })
    not_found = Net::HTTPNotFound.new('1.1', '404', 'Not Found')
    Net::HTTP.any_instance.stubs(:request)
             .returns(conflict, remote, no_content_response, not_found)

    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      Rails.logger.expects(:error).never
      build_issue.save!
    end
  end

  # A failing deletion is reported like any other broker failure.
  def test_failed_stale_attribute_deletion_is_logged
    conflict = Net::HTTPConflict.new('1.1', '409', 'Conflict')
    remote = remote_entity_response('assignee' => { 'type' => 'Property', 'value' => 'x' })
    Net::HTTP.any_instance.stubs(:request)
             .returns(conflict, remote, no_content_response, error_response)

    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      Rails.logger.expects(:error).with { |msg| msg.include?('answered 500') }
      build_issue.save!
    end
  end

  # An unreadable broker entity skips the deletion pass for this run (the
  # next update gets another chance); the append itself must still happen.
  def test_conflict_with_a_failed_read_back_still_appends
    conflict = Net::HTTPConflict.new('1.1', '409', 'Conflict')
    requests = []
    responses = [conflict, error_response, no_content_response]
    Net::HTTP.any_instance.stubs(:request).with { |req| requests << req; true }
             .returns(*responses)

    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      Rails.logger.expects(:error).never
      build_issue.save!
    end

    assert requests.any? { |r| r.is_a?(Net::HTTP::Post) && r.path.end_with?('/attrs') },
           'the append must run even when the read-back failed'
    assert_not requests.any? { |r| r.is_a?(Net::HTTP::Patch) }
  end

  # The read-back and the deletions send the entity's own context (#156), so
  # the broker names attributes as the entity does and a deletion by short
  # name hits the right attribute.
  def test_read_back_and_deletions_send_the_entity_context
    conflict = Net::HTTPConflict.new('1.1', '409', 'Conflict')
    remote = remote_entity_response('assignee' => { 'type' => 'Property', 'value' => 'x' })
    requests = []
    Net::HTTP.any_instance.stubs(:request).with { |req| requests << req; true }
             .returns(conflict, remote, no_content_response, no_content_response)

    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS, host_name: 'gtt.example.org', protocol: 'https' do
      build_issue.save!
    end

    link = %(<https://gtt.example.org/fiware/task-context.jsonld>; rel="http://www.w3.org/ns/json-ld#context"; type="application/ld+json")
    get = requests.find { |r| r.is_a?(Net::HTTP::Get) }
    assert_equal link, get['Link']
    delete = requests.find { |r| r.is_a?(Net::HTTP::Delete) }
    assert delete.path.end_with?('/attrs/assignee')
    assert_equal link, delete['Link']
    append = requests.find { |r| r.is_a?(Net::HTTP::Post) && r.path.end_with?('/attrs') }
    assert_nil append['Link'], 'a body carries its own @context'
  end

  # A broker that answers expanded names (it did not compact with our
  # context) must not make every attribute look stale (#156): full IRIs
  # (https:, urn:) and prefixed names are never deleted.
  def test_expanded_names_in_the_read_back_are_never_deleted
    conflict = Net::HTTPConflict.new('1.1', '409', 'Conflict')
    remote = remote_entity_response(
      'https://datamodels.jp/ns/task/progress' => { 'type' => 'Property', 'value' => 'needs-action' },
      'https://uri.etsi.org/ngsi-ld/default-context/name' => { 'type' => 'Property', 'value' => 'x' },
      'urn:example:term:assignee' => { 'type' => 'Property', 'value' => 'x' },
      'redmine:category' => { 'type' => 'Property', 'value' => 'x' }
    )
    requests = []
    Net::HTTP.any_instance.stubs(:request).with { |req| requests << req; true }
             .returns(conflict, remote, no_content_response)

    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      Rails.logger.expects(:error).never
      build_issue.save!
    end

    assert_not requests.any? { |r| r.is_a?(Net::HTTP::Delete) },
               'attributes named by IRIs or prefixed names must not be deleted'
  end

  # Without a host the instance context is out of reach; the read-back
  # names the redmine subject's public context instead.
  def test_link_header_without_a_host_names_the_redmine_context
    conflict = Net::HTTPConflict.new('1.1', '409', 'Conflict')
    requests = []
    Net::HTTP.any_instance.stubs(:request).with { |req| requests << req; true }
             .returns(conflict, remote_entity_response, no_content_response)

    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS, host_name: '' do
      build_issue.save!
    end

    get = requests.find { |r| r.is_a?(Net::HTTP::Get) }
    assert_equal %(<#{RedmineGttFiware::EmissionVocabulary::TASK_EXTENSION_CONTEXT}>; rel="http://www.w3.org/ns/json-ld#context"; type="application/ld+json"),
                 get['Link']
  end

  # --- entities left over from the retired GTT core vocabulary (#152) --------

  def legacy_conflict(type, *after)
    requests = []
    Net::HTTP.any_instance.stubs(:request).with { |req| requests << req; true }
             .returns(Net::HTTPConflict.new('1.1', '409', 'Conflict'),
                      remote_entity_response('type' => type), *after)
    requests
  end

  # An append never changes the entity type: a broker that still holds a
  # GTT-core Issue under the same id gets it deleted and created anew. Our
  # context cannot compact the old type, so the broker answers it as the
  # full IRI: of the retired namespace (emitted with a host name) or of the
  # NGSI-LD default context (emitted without one). The short name Issue is
  # the same in both vocabularies; only the IRI tells them apart.
  def test_a_legacy_gtt_core_entity_is_recreated
    ['https://gtt-project.org/ns/fiware#Issue',
     'https://uri.etsi.org/ngsi-ld/default-context/Issue'].each do |legacy_type|
      requests = legacy_conflict(legacy_type, no_content_response, created_response)

      with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
        build_issue.save!
      end

      delete = requests.find { |r| r.is_a?(Net::HTTP::Delete) }
      assert_not_nil delete, "#{legacy_type}: the old entity must be deleted"
      assert_match %r{/ngsi-ld/v1/entities/urn:ngsi-ld:Issue:redmine:test-town:\d+\z}, delete.path
      create = requests.last
      assert create.is_a?(Net::HTTP::Post)
      assert_equal '/ngsi-ld/v1/entities', create.path
      assert_equal 'Issue', JSON.parse(create.body)['type']
      assert_not requests.any? { |r| r.path.end_with?('/attrs') }, 'no attribute append on a type change'
    end
  end

  # Our own type, read back under any of its names (the redmine subject's
  # Issue, datamodels.jp's Task, or the IRI when the broker cannot compact),
  # is the same type: updated in place, never recreated.
  def test_own_type_under_any_name_is_not_recreated
    ['Issue', 'Task', 'https://datamodels.jp/ns/task/Task'].each do |own_type|
      requests = legacy_conflict(own_type, no_content_response)

      with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
        build_issue.save!
      end

      assert requests.any? { |r| r.is_a?(Net::HTTP::Post) && r.path.end_with?('/attrs') }, own_type
      assert_not requests.any? { |r| r.is_a?(Net::HTTP::Delete) }, own_type
    end
  end

  def test_failed_deletion_of_a_legacy_entity_is_logged
    requests = legacy_conflict('https://gtt-project.org/ns/fiware#Issue', error_response)

    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      Rails.logger.expects(:error).with { |msg| msg.include?('answered 500') }
      build_issue.save!
    end
    assert_equal 3, requests.length, 'no create after a failed deletion'
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

  # 409 -> append fallback where the append also fails: the failure of the
  # update request is the one reported.
  def test_conflict_then_failed_append_is_logged
    conflict = Net::HTTPConflict.new('1.1', '409', 'Conflict')
    responses = [conflict, remote_entity_response, error_response]
    requests = []
    Net::HTTP.any_instance.stubs(:request).with { |req| requests << req; true }
             .returns(*responses)
    with_settings plugin_redmine_gtt_fiware: EMISSION_SETTINGS do
      Rails.logger.expects(:error).with { |msg| msg.include?('answered 500') }
      build_issue.save!
    end
    assert requests.any? { |r| r.is_a?(Net::HTTP::Post) && r.path.end_with?('/attrs') },
           'the 409 must trigger the append fallback'
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
