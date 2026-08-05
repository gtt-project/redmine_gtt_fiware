require File.expand_path('../../test_helper', __FILE__)

# The form-state derivations behind the template form partials (#145): geo
# area and issue geometry radio state, watched attributes formatting, and the
# structured-picker/JSON-mode decision for entities and attachments.
class SubscriptionTemplateFormHelperTest < ActiveSupport::TestCase
  include SubscriptionTemplateFormHelper

  def template(attributes = {})
    SubscriptionTemplate.new(attributes)
  end

  # --- geo area mode ----------------------------------------------------------

  def test_geo_mode_is_anywhere_without_a_georel
    assert_equal 'anywhere', gtt_fiware_geo_mode(template, true)
  end

  def test_geo_mode_is_boundary_for_the_project_polygon_triple
    boundary = template(expression_georel: 'coveredBy', expression_geometry: 'polygon',
                        expression_coords: '1,2;3,4;1,2')
    assert_equal 'boundary', gtt_fiware_geo_mode(boundary, true)
  end

  # Without the boundary radio the same stored triple must show as a custom
  # query, not silently map to a radio that is not rendered.
  def test_geo_mode_falls_back_to_custom_when_the_boundary_is_unavailable
    boundary = template(expression_georel: 'coveredBy', expression_geometry: 'polygon')
    assert_equal 'custom', gtt_fiware_geo_mode(boundary, false)
  end

  def test_geo_mode_is_custom_for_other_geo_queries
    near = template(expression_georel: 'near;maxDistance:1000', expression_geometry: 'point')
    assert_equal 'custom', gtt_fiware_geo_mode(near, true)
  end

  # --- project boundary availability ------------------------------------------

  def test_boundary_requires_the_gtt_module_and_a_polygon
    project = stub(module_enabled?: true, geom: 'geom',
                   geojson: { 'geometry' => { 'type' => 'Polygon', 'coordinates' => [] } })
    assert gtt_fiware_project_boundary_available?(project)

    no_module = stub(module_enabled?: false)
    assert_not gtt_fiware_project_boundary_available?(no_module)

    point = stub(module_enabled?: true, geom: 'geom',
                 geojson: { 'geometry' => { 'type' => 'Point', 'coordinates' => [] } })
    assert_not gtt_fiware_project_boundary_available?(point)
  end

  # --- watched attributes -----------------------------------------------------

  def test_watched_attrs_list_joins_the_stored_array
    assert_equal 'severity, status', gtt_fiware_watched_attrs_list(template(attrs: '["severity","status"]'))
  end

  def test_watched_attrs_list_is_blank_for_non_arrays_and_bad_json
    assert_equal '', gtt_fiware_watched_attrs_list(template(attrs: '{"a":1}'))
    assert_equal '', gtt_fiware_watched_attrs_list(template(attrs: 'not json'))
    assert_equal '', gtt_fiware_watched_attrs_list(template)
  end

  # --- entity picker ----------------------------------------------------------

  def test_entity_picker_offers_a_starter_row_for_a_blank_template
    picker = gtt_fiware_entity_picker(template)
    assert picker.pickerable?
    assert_equal [{ 'type' => '', 'idPattern' => '.*' }], picker.rows
  end

  def test_entity_picker_accepts_flat_type_and_pattern_rows
    entities = [{ 'type' => 'RoadDamage', 'idPattern' => '.*' }, { 'type' => 'Sensor', 'id' => 'urn:x:1' }]
    picker = gtt_fiware_entity_picker(template(entities: entities))
    assert picker.pickerable?
    assert_equal entities, picker.rows
  end

  def test_entity_picker_falls_back_to_json_mode_for_richer_entries
    extra_key = [{ 'type' => 'Sensor', 'idPattern' => '.*', 'scope' => '/x' }]
    assert_not gtt_fiware_entity_picker(template(entities: extra_key)).pickerable?

    both_matchers = [{ 'type' => 'Sensor', 'idPattern' => '.*', 'id' => 'urn:x:1' }]
    assert_not gtt_fiware_entity_picker(template(entities: both_matchers)).pickerable?

    no_type = [{ 'idPattern' => '.*' }]
    assert_not gtt_fiware_entity_picker(template(entities: no_type)).pickerable?
  end

  # --- issue geometry mode ----------------------------------------------------

  def test_geometry_mode_defaults_new_templates_to_the_entity_location
    assert_equal 'location', gtt_fiware_geometry_mode(template)
  end

  def test_geometry_mode_keeps_a_stored_blank_as_none
    persisted = template
    persisted.stubs(:new_record?).returns(false)
    assert_equal 'none', gtt_fiware_geometry_mode(persisted)
  end

  def test_geometry_mode_recognizes_the_location_placeholder_and_custom_json
    assert_equal 'location', gtt_fiware_geometry_mode(template(geometry: '${location}'))
    assert_equal 'custom', gtt_fiware_geometry_mode(template(geometry: { 'type' => 'Point' }))
  end

  # --- attachment picker ------------------------------------------------------

  def test_attachment_picker_offers_a_starter_row_for_a_blank_template
    picker = gtt_fiware_attachment_picker(template)
    assert picker.pickerable?
    assert_equal [{}], picker.rows
  end

  def test_attachment_picker_falls_back_to_json_mode_for_unknown_keys
    rows = [{ 'url' => 'https://x', 'headers' => { 'X' => 'y' } }]
    assert_not gtt_fiware_attachment_picker(template(attachments: rows)).pickerable?
  end
end
