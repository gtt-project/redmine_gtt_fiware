require File.expand_path('../../test_helper', __FILE__)

class TemplateRendererTest < ActiveSupport::TestCase
  Entity = RedmineGttFiware::Entity
  Renderer = RedmineGttFiware::TemplateRenderer

  def entity
    Entity.from({
      'id' => 'urn:ngsi-ld:TemperatureSensor:001',
      'type' => 'TemperatureSensor',
      'temperature' => { 'type' => 'Property', 'value' => 21.5 },
      'location' => { 'type' => 'GeoProperty', 'value' => { 'type' => 'Point', 'coordinates' => [135.5, 34.7] } },
    }, 'NGSI-LD')
  end

  def test_renders_scalar_expressions
    assert_equal 'Sensor urn:ngsi-ld:TemperatureSensor:001: 21.5',
                 Renderer.render('Sensor ${id}: ${attrs.temperature.value}', entity)
  end

  def test_renders_missing_path_as_empty_string
    assert_equal 'x=', Renderer.render('x=${attrs.nope.value}', entity)
  end

  def test_returns_nil_for_nil_template
    assert_nil Renderer.render(nil, entity)
  end

  def test_stringifies_a_hash_value_as_json
    assert_equal 'loc={"type":"Point","coordinates":[135.5,34.7]}',
                 Renderer.render('loc=${location}', entity)
  end

  def test_render_geometry_substitutes_structurally
    template = { 'type' => 'Feature', 'geometry' => '${location}' }
    assert_equal({ 'type' => 'Feature', 'geometry' => { 'type' => 'Point', 'coordinates' => [135.5, 34.7] } },
                 Renderer.render_geometry(template, entity))
  end

  def test_render_geometry_nil_passthrough
    assert_nil Renderer.render_geometry(nil, entity)
  end
end
