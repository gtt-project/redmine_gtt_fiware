require File.expand_path('../../test_helper', __FILE__)

class IssueEntityTest < ActiveSupport::TestCase
  fixtures :projects, :trackers, :projects_trackers, :issue_statuses,
           :users, :email_addresses, :enumerations, :issues,
           :versions, :issue_categories

  def setup
    @connection = BrokerConnection.create!(
      name: 'Entity broker', standard: 'NGSI-LD',
      url: 'https://broker.example.com', auth_mode: 'stored'
    )
    @mapping = EmissionMapping.create!(
      broker_connection: @connection, tracker: Tracker.find(1), subtype: 'WorkOrder'
    )
    @issue = Issue.find(1)
  end

  def entity(issue = @issue)
    with_settings plugin_redmine_gtt_fiware: { 'fiware_instance_id' => 'test-town' },
                  host_name: 'redmine.example.com', protocol: 'https' do
      return RedmineGttFiware::IssueEntity.new(issue, @mapping).to_h
    end
  end

  def test_core_properties
    e = entity
    assert_equal "urn:ngsi-ld:Issue:redmine:test-town:#{@issue.id}", e['id']
    assert_equal 'Issue', e['type']
    assert_equal @issue.subject, e.dig('title', 'value')
    assert_equal 'open', e.dig('status', 'value')
    assert_equal @issue.status.name, e.dig('statusLabel', 'value')
    assert_equal 'WorkOrder', e.dig('subtype', 'value')
    assert_equal "https://redmine.example.com/issues/#{@issue.id}", e.dig('source', 'value')
    assert_equal 'DateTime', e.dig('dateCreated', 'value', '@type')
    # With a public host the entity references the instance's published
    # context ahead of the core one, so subtype terms expand properly.
    assert_equal ['https://redmine.example.com/fiware/context.jsonld',
                  RedmineGttFiware::IssueEntity::CORE_CONTEXT], e['@context']
  end

  # Brokers dereference @context at ingestion: an instance without a public
  # identity must not point them at an unreachable URL.
  def test_context_is_core_only_without_a_configured_host
    with_settings plugin_redmine_gtt_fiware: { 'fiware_instance_id' => 'test-town' }, host_name: '' do
      e = RedmineGttFiware::IssueEntity.new(@issue, @mapping).to_h
      assert_equal RedmineGttFiware::IssueEntity::CORE_CONTEXT, e['@context']
    end
  end

  def test_status_normalizes_to_closed_for_closed_statuses
    @issue.status = IssueStatus.where(is_closed: true).first
    e = entity
    assert_equal 'closed', e.dig('status', 'value')
    assert_equal @issue.status.name, e.dig('statusLabel', 'value')
  end

  # GTT's Z-enabled factory encodes 2D data with a zero third coordinate;
  # strict brokers (GeonicDB) reject anything but [lon, lat] pairs, so the
  # zero-Z artifact is stripped while a real altitude is kept.
  def test_location_from_issue_geometry_strips_the_zero_z_artifact
    @issue.geom = RedmineGtt::Conversions.to_geom(
      '{"type":"Feature","geometry":{"type":"Point","coordinates":[139.69,35.69]},"properties":null}'
    )
    e = entity
    assert_equal 'GeoProperty', e.dig('location', 'type')
    assert_equal 'Point', e.dig('location', 'value')['type']
    assert_equal [139.69, 35.69], e.dig('location', 'value')['coordinates']
  end

  def test_location_keeps_a_real_altitude
    @issue.geom = RedmineGtt::Conversions.to_geom(
      '{"type":"Feature","geometry":{"type":"Point","coordinates":[139.69,35.69,42.5]},"properties":null}'
    )
    assert_equal [139.69, 35.69, 42.5], entity.dig('location', 'value')['coordinates']
  end

  def test_location_strips_zero_z_from_nested_coordinates
    @issue.geom = RedmineGtt::Conversions.to_geom(
      '{"type":"Feature","geometry":{"type":"LineString","coordinates":[[139.6,35.6,0.0],[139.7,35.7,0.0]]},"properties":null}'
    )
    assert_equal [[139.6, 35.6], [139.7, 35.7]], entity.dig('location', 'value')['coordinates']
  end

  def test_no_location_without_geometry
    assert_nil entity['location']
  end

  def test_refers_to_only_for_uri_shaped_entity_ids
    @issue.fiware_entity = 'urn:ngsi-ld:WasteContainer:042'
    assert_equal 'urn:ngsi-ld:WasteContainer:042', entity.dig('refersTo', 'object')

    @issue.fiware_entity = 'not a uri'
    assert_nil entity['refersTo']
  end

  # --- exposed standard fields (#69, step 2b) --------------------------------

  # Nothing beyond the frozen core is emitted unless the admin exposed it.
  def test_no_standard_fields_without_exposure
    @issue.priority = IssuePriority.first
    e = entity
    assert_nil e['priority']
    assert_nil e['description']
    assert_nil e['assignee']
  end

  def test_exposed_fields_are_emitted
    @mapping.exposed_standard_fields = %w[priority percentDone startDate assignee parent]
    @mapping.save!
    @issue.start_date = Date.new(2026, 7, 30)
    @issue.assigned_to = User.active.first
    @issue.done_ratio = 40

    e = entity
    assert_equal @issue.priority.name, e.dig('priority', 'value')
    assert_equal 40, e.dig('percentDone', 'value')
    assert_equal({ '@type' => 'Date', '@value' => '2026-07-30' }, e.dig('startDate', 'value'))
    assert_equal User.active.first.name, e.dig('assignee', 'value')
    # priority exposed but description not: exposure is per field.
    assert_nil e['description']
  end

  # Absent data is absent from the entity, not null-valued (fixture issue 1
  # carries a category, so it is cleared explicitly).
  def test_exposed_fields_without_values_are_omitted
    @mapping.exposed_standard_fields = %w[category targetVersion dueDate assignee]
    @mapping.save!
    @issue.category = nil
    @issue.fixed_version = nil
    @issue.due_date = nil
    @issue.assigned_to = nil
    e = entity
    assert_nil e['category']
    assert_nil e['targetVersion']
    assert_nil e['dueDate']
    assert_nil e['assignee']
  end

  def test_exposed_parent_is_a_relationship_to_the_parent_urn
    @mapping.exposed_standard_fields = %w[parent]
    @mapping.save!
    # parent reads the persisted hierarchy; stubbing keeps the test free of
    # nested-set writes (and of emission side effects on save).
    parent = Issue.find(2)
    @issue.stubs(:parent).returns(parent)

    e = entity
    assert_equal 'Relationship', e.dig('parent', 'type')
    assert_equal "urn:ngsi-ld:Issue:redmine:test-town:#{parent.id}", e.dig('parent', 'object')
  end

  # --- exposed custom fields (#69, step 2c) ----------------------------------

  def custom_field(format, name)
    IssueCustomField.create!(name: name, field_format: format, is_for_all: true,
                             trackers: Tracker.all)
  end

  def test_exposed_custom_fields_are_typed_by_format
    string_cf = custom_field('string', 'Road surface')
    bool_cf = custom_field('bool', 'On-site verified')
    int_cf = custom_field('int', 'Severity score')
    date_cf = custom_field('date', 'Inspection date')
    @mapping.exposed_custom_fields = {
      string_cf.id => 'roadSurface', bool_cf.id => 'onSiteVerified',
      int_cf.id => 'severityScore', date_cf.id => 'inspectionDate'
    }
    @mapping.save!
    @issue.custom_field_values = {
      string_cf.id => 'gravel', bool_cf.id => '0',
      int_cf.id => '4', date_cf.id => '2026-07-30'
    }

    e = entity
    assert_equal 'gravel', e.dig('roadSurface', 'value')
    assert_equal false, e.dig('onSiteVerified', 'value')
    assert_equal 4, e.dig('severityScore', 'value')
    assert_equal({ '@type' => 'Date', '@value' => '2026-07-30' }, e.dig('inspectionDate', 'value'))
  end

  def test_blank_custom_values_are_omitted
    string_cf = custom_field('string', 'Road surface')
    @mapping.exposed_custom_fields = { string_cf.id => 'roadSurface' }
    @mapping.save!
    @issue.custom_field_values = { string_cf.id => '' }

    assert_nil entity['roadSurface']
  end

  def test_deleted_custom_fields_are_skipped
    @mapping.exposed_custom_fields = { 99_999 => 'ghostField' }
    @mapping.save!
    assert_nil entity['ghostField']
  end

  # A pre-validation mapping row with a blank subtype must not emit a
  # null-valued property.
  def test_blank_subtype_is_absent
    @mapping.subtype = ''
    assert_nil entity['subtype']
  end

  # Pull-side rendering (#4): without a mapping the representation is the
  # frozen core alone.
  def test_renders_the_core_alone_without_a_mapping
    with_settings plugin_redmine_gtt_fiware: { 'fiware_instance_id' => 'test-town' } do
      e = RedmineGttFiware::IssueEntity.new(@issue).to_h
      assert_equal 'Issue', e['type']
      assert_nil e['subtype']
      assert_nil e['priority']
    end
  end

  def test_source_omitted_without_a_configured_host
    with_settings plugin_redmine_gtt_fiware: { 'fiware_instance_id' => 'test-town' }, host_name: '' do
      e = RedmineGttFiware::IssueEntity.new(@issue, @mapping).to_h
      assert_nil e['source']
    end
  end

  # --- the task vocabulary (#152) ---------------------------------------------

  TASK_SETTINGS = { 'fiware_instance_id' => 'test-town', 'fiware_emission_vocabulary' => 'task' }.freeze

  def task_entity(issue = @issue, mapping = @mapping)
    with_settings plugin_redmine_gtt_fiware: TASK_SETTINGS,
                  host_name: 'redmine.example.com', protocol: 'https' do
      return RedmineGttFiware::IssueEntity.build(issue, mapping).to_h
    end
  end

  # gtt stays the default: without the setting (existing instances) and with
  # an unknown value, the representation is exactly the frozen core one.
  def test_default_vocabulary_is_the_gtt_core
    [{}, { 'fiware_emission_vocabulary' => 'gtt' }, { 'fiware_emission_vocabulary' => 'bogus' }].each do |extra|
      with_settings plugin_redmine_gtt_fiware: { 'fiware_instance_id' => 'test-town' }.merge(extra),
                    host_name: 'redmine.example.com', protocol: 'https' do
        built = RedmineGttFiware::IssueEntity.build(@issue, @mapping)
        assert_instance_of RedmineGttFiware::IssueEntity, built
        assert_equal RedmineGttFiware::IssueEntity.new(@issue, @mapping).to_h, built.to_h
        assert_equal 'Issue', built.to_h['type']
      end
    end
  end

  def test_task_mode_always_emitted_properties
    e = task_entity
    # The id stays the IssueUrn, so switching never re-identifies an entity.
    assert_equal "urn:ngsi-ld:Issue:redmine:test-town:#{@issue.id}", e['id']
    assert_equal 'Task', e['type']
    assert_equal @issue.subject, e.dig('name', 'value')
    assert_equal 'needs-action', e.dig('progress', 'value')
    assert_equal @issue.status.name, e.dig('statusLabel', 'value')
    assert_equal 'WorkOrder', e.dig('subtype', 'value')
    assert_equal "https://redmine.example.com/issues/#{@issue.id}", e.dig('source', 'value')
    assert_equal @issue.id.to_s, e.dig('externalId', 'value')
    assert_equal 'Relationship', e.dig('project', 'type')
    assert_equal "urn:ngsi-ld:Project:redmine:test-town:#{@issue.project.identifier}",
                 e.dig('project', 'object')
    assert_equal 'DateTime', e.dig('dateCreated', 'value', '@type')
    assert_equal 'DateTime', e.dig('dateModified', 'value', '@type')
    assert_equal ['https://redmine.example.com/fiware/task-context.jsonld',
                  RedmineGttFiware::IssueEntity::CORE_CONTEXT], e['@context']
    # No GTT core term leaks into a Task.
    %w[title status].each { |term| assert_nil e[term], "#{term} must not be emitted" }
  end

  def test_task_mode_context_is_core_only_without_a_configured_host
    with_settings plugin_redmine_gtt_fiware: TASK_SETTINGS, host_name: '' do
      e = RedmineGttFiware::IssueEntity.build(@issue, @mapping).to_h
      assert_equal RedmineGttFiware::IssueEntity::CORE_CONTEXT, e['@context']
      assert_nil e['source']
    end
  end

  def test_task_mode_progress_is_completed_for_closed_statuses
    @issue.status = IssueStatus.where(is_closed: true).first
    e = task_entity
    assert_equal 'completed', e.dig('progress', 'value')
    assert_equal @issue.status.name, e.dig('statusLabel', 'value')
  end

  def test_task_mode_location_and_refers_to
    @issue.geom = RedmineGtt::Conversions.to_geom(
      '{"type":"Feature","geometry":{"type":"Point","coordinates":[139.69,35.69]},"properties":null}'
    )
    @issue.fiware_entity = 'urn:ngsi-ld:WasteContainer:042'
    e = task_entity
    assert_equal [139.69, 35.69], e.dig('location', 'value')['coordinates']
    assert_equal 'urn:ngsi-ld:WasteContainer:042', e.dig('refersTo', 'object')
  end

  # Nothing beyond the always-emitted properties unless the admin exposed it.
  def test_task_mode_no_standard_fields_without_exposure
    e = task_entity
    %w[description priority category milestone start due estimatedDuration
       percentComplete parent assignee].each do |term|
      assert_nil e[term], "#{term} must not be emitted without exposure"
    end
  end

  def test_task_mode_exposed_fields_use_task_terms
    @mapping.exposed_standard_fields = EmissionMapping::STANDARD_FIELDS.keys
    @mapping.save!
    @issue.description = 'Pothole next to the bus stop'
    @issue.priority = IssuePriority.active.sorted.last
    @issue.category = IssueCategory.find(1)
    @issue.fixed_version = Version.find(2)
    @issue.start_date = Date.new(2026, 7, 30)
    @issue.due_date = Date.new(2026, 8, 15)
    @issue.estimated_hours = 1.5
    @issue.done_ratio = 40
    @issue.assigned_to = User.find(2)
    parent = Issue.find(2)
    @issue.stubs(:parent).returns(parent)

    e = task_entity
    assert_equal 'Pothole next to the bus stop', e.dig('description', 'value')
    assert_equal 1, e.dig('priority', 'value'), 'the highest active priority ranks 1'
    assert_equal IssueCategory.find(1).name, e.dig('category', 'value')
    assert_equal 'Relationship', e.dig('milestone', 'type')
    assert_equal 'urn:ngsi-ld:Milestone:redmine:test-town:2', e.dig('milestone', 'object')
    assert_equal({ '@type' => 'Date', '@value' => '2026-07-30' }, e.dig('start', 'value'))
    assert_equal({ '@type' => 'Date', '@value' => '2026-08-15' }, e.dig('due', 'value'))
    assert_equal 'PT1H30M', e.dig('estimatedDuration', 'value')
    assert_equal 40, e.dig('percentComplete', 'value')
    assert_equal "urn:ngsi-ld:Issue:redmine:test-town:#{parent.id}", e.dig('parent', 'object')
    assert_equal [{ 'type' => 'Relationship', 'object' => 'urn:ngsi-ld:Person:redmine:test-town:2',
                    'datasetId' => 'urn:ngsi-ld:dataset:assignee:1' }], e['assignee']
    # The GTT names of the same fields are not emitted.
    %w[targetVersion startDate dueDate estimatedTime percentDone].each do |term|
      assert_nil e[term], "#{term} is a GTT term"
    end
  end

  # Absent data is absent from a Task too, not null-valued.
  def test_task_mode_exposed_fields_without_values_are_omitted
    @mapping.exposed_standard_fields = EmissionMapping::STANDARD_FIELDS.keys
    @mapping.save!
    @issue.description = ''
    @issue.category = nil
    @issue.fixed_version = nil
    @issue.start_date = nil
    @issue.due_date = nil
    @issue.estimated_hours = nil
    @issue.assigned_to = nil
    @issue.stubs(:parent).returns(nil)

    e = task_entity
    %w[description category milestone start due estimatedDuration parent assignee].each do |term|
      assert_nil e[term], "#{term} must be absent without a value"
    end
  end

  def test_task_mode_group_assignee_points_at_a_group
    @mapping.exposed_standard_fields = %w[assignee]
    @mapping.save!
    group = Group.find(10)
    @issue.assigned_to = group

    assignee = task_entity['assignee']
    assert_equal 1, assignee.size
    assert_equal "urn:ngsi-ld:Group:redmine:test-town:#{group.id}", assignee.first['object']
    assert_equal 'urn:ngsi-ld:dataset:assignee:1', assignee.first['datasetId']
  end

  # RFC 8984: 1 highest, 9 lowest, spread linearly over the active
  # priorities and rounded; 0 means undefined.
  def test_priority_rank_spreads_active_priorities_over_one_to_nine
    IssuePriority.update_all(active: false)
    low, normal, high, urgent = %w[RankLow RankNormal RankHigh RankUrgent].map do |name|
      IssuePriority.create!(name: name, active: true)
    end

    rank = ->(priority) { RedmineGttFiware::TaskEntity.priority_rank(priority) }
    assert_equal 1, rank.call(urgent)
    assert_equal 4, rank.call(high)
    assert_equal 6, rank.call(normal)
    assert_equal 9, rank.call(low)
  end

  def test_priority_rank_is_zero_for_a_single_active_priority
    IssuePriority.update_all(active: false)
    only = IssuePriority.create!(name: 'RankOnly', active: true)
    assert_equal 0, RedmineGttFiware::TaskEntity.priority_rank(only)
  end

  def test_priority_rank_is_zero_for_an_inactive_priority
    inactive = IssuePriority.active.sorted.first
    inactive.update_column(:active, false)
    assert_equal 0, RedmineGttFiware::TaskEntity.priority_rank(inactive)
  end

  def test_estimated_hours_become_an_iso8601_duration
    {
      1.5 => 'PT1H30M', 2 => 'PT2H', 0.25 => 'PT15M', 100 => 'PT100H',
      1.999 => 'PT2H', 0.1 => 'PT6M', 0.001 => 'PT0M', 0 => 'PT0M'
    }.each do |hours, expected|
      assert_equal expected, RedmineGttFiware::TaskEntity.iso8601_duration(hours), "#{hours} hours"
    end
  end

  def test_task_mode_exposed_custom_fields_keep_their_instance_terms
    string_cf = custom_field('string', 'Road surface')
    @mapping.exposed_custom_fields = { string_cf.id => 'roadSurface' }
    @mapping.save!
    @issue.custom_field_values = { string_cf.id => 'gravel' }

    assert_equal 'gravel', task_entity.dig('roadSurface', 'value')
  end

  # A custom term saved while the instance emitted the GTT vocabulary may
  # collide with a task term; in task mode it is dropped rather than
  # overwriting the task attribute.
  def test_task_mode_drops_custom_terms_that_shadow_task_terms
    string_cf = custom_field('string', 'Deadline note')
    @mapping.exposed_custom_fields = { string_cf.id => 'due' }
    @mapping.save!
    @issue.custom_field_values = { string_cf.id => 'end of month' }
    @issue.due_date = nil

    assert_nil task_entity['due']
  end

  # Pull-side rendering (#4) in task mode: the always-emitted properties
  # alone.
  def test_task_mode_renders_without_a_mapping
    e = task_entity(@issue, nil)
    assert_equal 'Task', e['type']
    assert_nil e['subtype']
    assert_nil e['priority']
    assert_equal "urn:ngsi-ld:Project:redmine:test-town:#{@issue.project.identifier}",
                 e.dig('project', 'object')
  end
end
