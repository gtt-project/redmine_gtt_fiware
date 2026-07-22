require File.expand_path('../../test_helper', __FILE__)

class EntityTest < ActiveSupport::TestCase
  Entity = RedmineGttFiware::Entity

  def ngsi_ld_entity(overrides = {})
    {
      'id' => 'urn:ngsi-ld:TemperatureSensor:001',
      'type' => 'TemperatureSensor',
      '@context' => 'https://example/context.jsonld',
      'temperature' => { 'type' => 'Property', 'value' => 21.5, 'unitCode' => 'CEL' },
      'owner' => { 'type' => 'Relationship', 'object' => 'urn:ngsi-ld:Person:42' },
      'location' => { 'type' => 'GeoProperty', 'value' => { 'type' => 'Point', 'coordinates' => [135.5, 34.7] } },
    }.merge(overrides)
  end

  def ngsi_v2_entity(overrides = {})
    {
      'id' => 'Sensor:001',
      'type' => 'TemperatureSensor',
      'temperature' => { 'type' => 'Number', 'value' => 30, 'metadata' => { 'unitCode' => { 'value' => 'CEL' } } },
      'location' => { 'type' => 'geo:json', 'value' => { 'type' => 'Point', 'coordinates' => [1, 2] } },
    }.merge(overrides)
  end

  def test_normalizes_ngsi_ld_id_and_type
    e = Entity.from(ngsi_ld_entity, 'NGSI-LD')
    assert_equal 'urn:ngsi-ld:TemperatureSensor:001', e.id
    assert_equal 'TemperatureSensor', e.type
  end

  def test_resolves_ngsi_ld_property_value
    e = Entity.from(ngsi_ld_entity, 'NGSI-LD')
    assert_equal 21.5, e.resolve('attrs.temperature.value')
    assert_equal 21.5, e.resolve('temperature.value')
    assert_equal 21.5, e.resolve('temperature') # shorthand
  end

  def test_resolves_ngsi_ld_relationship_object_as_value
    e = Entity.from(ngsi_ld_entity, 'NGSI-LD')
    assert_equal 'urn:ngsi-ld:Person:42', e.resolve('owner')
  end

  def test_extracts_ngsi_ld_geoproperty_as_geometry
    e = Entity.from(ngsi_ld_entity, 'NGSI-LD')
    assert_equal({ 'type' => 'Point', 'coordinates' => [135.5, 34.7] }, e.geometry)
  end

  def test_ignores_context_and_unknown_paths
    e = Entity.from(ngsi_ld_entity, 'NGSI-LD')
    assert_nil e.resolve('@context')
    assert_nil e.resolve('humidity.value')
    assert_nil e.resolve('')
  end

  def test_normalizes_ngsi_v2_value_and_metadata
    e = Entity.from(ngsi_v2_entity, 'NGSIv2')
    assert_equal 30, e.resolve('attrs.temperature.value')
    assert_equal 'CEL', e.resolve('attrs.temperature.metadata.unitCode.value')
  end

  def test_extracts_ngsi_v2_geo_json_as_geometry
    e = Entity.from(ngsi_v2_entity, 'NGSIv2')
    assert_equal({ 'type' => 'Point', 'coordinates' => [1, 2] }, e.geometry)
  end

  def test_handles_non_hash_and_empty_entities
    e = Entity.from(nil, 'NGSI-LD')
    assert_nil e.id
    assert_nil e.geometry
    assert_nil e.resolve('anything')
  end
end
