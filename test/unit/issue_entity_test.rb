require File.expand_path('../../test_helper', __FILE__)

class IssueEntityTest < ActiveSupport::TestCase
  fixtures :projects, :trackers, :projects_trackers, :issue_statuses,
           :users, :email_addresses, :enumerations, :issues

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

  def test_source_omitted_without_a_configured_host
    with_settings plugin_redmine_gtt_fiware: { 'fiware_instance_id' => 'test-town' }, host_name: '' do
      e = RedmineGttFiware::IssueEntity.new(@issue, @mapping).to_h
      assert_nil e['source']
    end
  end
end
