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

  def test_source_omitted_without_a_configured_host
    with_settings plugin_redmine_gtt_fiware: { 'fiware_instance_id' => 'test-town' }, host_name: '' do
      e = RedmineGttFiware::IssueEntity.new(@issue, @mapping).to_h
      assert_nil e['source']
    end
  end
end
