require File.expand_path('../../test_helper', __FILE__)

class SubscriptionRequestTest < ActiveSupport::TestCase
  BASE_URL = 'https://redmine.example.com'.freeze

  # Builds an unsaved template (no DB write) with sensible defaults for the
  # given standard; overrides win.
  def template(standard, overrides = {})
    t = SubscriptionTemplate.new(
      {
        standard: standard,
        status: 'active',
        name: 'Temperature alerts',
        broker_url: 'https://broker.example.com',
        subject: 'Sensor ${id}',
        description: 'changed',
        context: 'https://uri.etsi.org/ngsi-ld/v1/ngsi-ld-core-context.jsonld'
      }.merge(overrides)
    )
    # Deterministic id without a DB write so callback URLs have a realistic
    # shape (`.../subscription_template/123/notification`).
    t.id = 123
    t.entities = [{ 'idPattern' => '.*', 'type' => 'TemperatureSensor' }]
    t.webhook_secret = 'secret-abc'
    t.alteration_types = overrides[:alteration_types] if overrides.key?(:alteration_types)
    t
  end

  def build(standard, overrides = {})
    RedmineGttFiware::SubscriptionRequest.build(template(standard, overrides), base_url: BASE_URL, throttling: 3)
  end

  def payload(standard, overrides = {})
    JSON.parse(build(standard, overrides).to_json)
  end

  # --- factory / URLs -------------------------------------------------------

  def test_build_selects_the_ngsi_v2_builder
    assert_instance_of RedmineGttFiware::SubscriptionRequest::NgsiV2, build('NGSIv2')
  end

  def test_build_selects_the_ngsi_ld_builder
    assert_instance_of RedmineGttFiware::SubscriptionRequest::NgsiLd, build('NGSI-LD')
  end

  def test_ngsi_v2_urls_use_the_v2_prefix
    req = build('NGSIv2')
    assert_equal 'https://broker.example.com/v2/subscriptions', req.subscriptions_url
    assert_equal 'https://broker.example.com/v2/entities', req.entities_url
  end

  def test_ngsi_ld_urls_use_the_ngsi_ld_prefix
    req = build('NGSI-LD')
    assert_equal 'https://broker.example.com/ngsi-ld/v1/subscriptions', req.subscriptions_url
    assert_equal 'https://broker.example.com/ngsi-ld/v1/entities', req.entities_url
  end

  def test_subscription_url_targets_the_current_subscription
    req = build('NGSI-LD', subscription_id: 'urn:ngsi-ld:Subscription:1')
    assert_equal 'https://broker.example.com/ngsi-ld/v1/subscriptions/urn:ngsi-ld:Subscription:1', req.subscription_url
  end

  # An explicit versioned path in the broker URL is preserved, with or without
  # a trailing slash (normalized to end with one).
  def test_ngsi_v2_preserves_a_versioned_broker_path_without_trailing_slash
    req = build('NGSIv2', broker_url: 'https://broker.example.com/orion/v2.1')
    assert_equal 'https://broker.example.com/orion/v2.1/subscriptions', req.subscriptions_url
  end

  def test_ngsi_v2_preserves_a_versioned_broker_path_with_trailing_slash
    req = build('NGSIv2', broker_url: 'https://broker.example.com/orion/v2.1/')
    assert_equal 'https://broker.example.com/orion/v2.1/subscriptions', req.subscriptions_url
  end

  def test_ngsi_ld_preserves_a_versioned_broker_path_without_trailing_slash
    req = build('NGSI-LD', broker_url: 'https://broker.example.com/broker/ngsi-ld/v1')
    assert_equal 'https://broker.example.com/broker/ngsi-ld/v1/subscriptions', req.subscriptions_url
  end

  # --- NGSIv2 payload -------------------------------------------------------

  def test_ngsi_v2_payload_shape
    p = payload('NGSIv2', alteration_types: %w[entityCreate entityChange])
    assert_equal [{ 'idPattern' => '.*', 'type' => 'TemperatureSensor' }], p.dig('subject', 'entities')
    assert_equal %w[entityCreate entityChange], p.dig('subject', 'condition', 'alterationTypes')
    assert_equal 3, p['throttling']
    assert_equal 'active', p['status']
  end

  def test_ngsi_v2_notification_carries_only_callback_and_headers_no_templating
    http_custom = payload('NGSIv2').dig('notification', 'httpCustom')
    assert_equal 'https://redmine.example.com/fiware/subscription_template/123/notification', http_custom['url']
    assert_equal 'POST', http_custom['method']
    assert_equal 'secret-abc', http_custom.dig('headers', 'X-Gtt-Webhook-Secret')
    # The broker does no field templating anymore (#64): no json block.
    assert_nil http_custom['json']
  end

  def test_ngsi_v2_builds_expression_when_geo_fields_and_query_present
    p = payload('NGSIv2',
                expression_georel: 'near;maxDistance==2000',
                expression_geometry: 'point',
                expression_coords: '135,35',
                expression_query: 'temperature>30')
    expr = p.dig('subject', 'condition', 'expression')
    assert_equal 'near;maxDistance==2000', expr['georel']
    assert_equal 'point', expr['geometry']
    assert_equal '135,35', expr['coords']
    assert_equal 'temperature>30', expr['q']
  end

  # --- NGSI-LD payload ------------------------------------------------------

  def test_ngsi_ld_payload_shape
    p = payload('NGSI-LD')
    assert_equal 'Subscription', p['type']
    assert_equal [{ 'idPattern' => '.*', 'type' => 'TemperatureSensor' }], p['entities']
    assert_equal 'normalized', p.dig('notification', 'format')
    assert_equal true, p['isActive']
    assert_equal 3, p['throttling']
  end

  def test_ngsi_ld_endpoint_carries_receiver_info_headers
    endpoint = payload('NGSI-LD').dig('notification', 'endpoint')
    assert_equal 'https://redmine.example.com/fiware/subscription_template/123/notification', endpoint['uri']
    secret = endpoint['receiverInfo'].find { |h| h['key'] == 'X-Gtt-Webhook-Secret' }
    assert_equal 'secret-abc', secret['value']
    assert endpoint['receiverInfo'].any? { |h| h['key'] == 'X-Redmine-GTT-Subscription-Template-URL' }
  end

  def test_ngsi_ld_context_url_passes_through
    p = payload('NGSI-LD', context: 'https://example.test/context.jsonld')
    assert_equal 'https://example.test/context.jsonld', p['@context']
  end

  def test_ngsi_ld_context_json_array_is_parsed
    p = payload('NGSI-LD', context: '["https://a.test/ctx.jsonld","https://b.test/ctx.jsonld"]')
    assert_equal ['https://a.test/ctx.jsonld', 'https://b.test/ctx.jsonld'], p['@context']
  end

  def test_ngsi_ld_maps_and_dedupes_notification_triggers
    p = payload('NGSI-LD', alteration_types: %w[entityCreate entityChange entityUpdate entityDelete])
    assert_equal %w[entityCreated entityUpdated entityDeleted], p['notificationTrigger']
  end

  # geoQ uses the `coordinates` key, and the stored NGSIv2 geometry name is
  # mapped to the GeoJSON type name NGSI-LD expects.
  def test_ngsi_ld_builds_geo_q_with_coordinates_key
    p = payload('NGSI-LD',
                expression_georel: 'near;maxDistance==2000',
                expression_geometry: 'point',
                expression_coords: '[135,35]')
    geo_q = p['geoQ']
    assert_equal 'near;maxDistance==2000', geo_q['georel']
    assert_equal 'Point', geo_q['geometry']
    assert_equal '[135,35]', geo_q['coordinates']
    assert_nil geo_q['coords']
  end

  def test_ngsi_ld_maps_line_and_polygon_geometry_names
    line = payload('NGSI-LD', expression_georel: 'intersects', expression_geometry: 'line', expression_coords: '[[0,0],[1,1]]')
    assert_equal 'LineString', line.dig('geoQ', 'geometry')
    polygon = payload('NGSI-LD', expression_georel: 'within', expression_geometry: 'polygon', expression_coords: '[[[0,0],[1,0],[1,1],[0,0]]]')
    assert_equal 'Polygon', polygon.dig('geoQ', 'geometry')
  end

  # `box` has no NGSI-LD equivalent: it passes through verbatim so the broker
  # rejects it with a clear error rather than the plugin guessing a shape.
  def test_ngsi_ld_passes_unmappable_box_geometry_through
    p = payload('NGSI-LD', expression_georel: 'within', expression_geometry: 'box', expression_coords: '[[0,0],[1,1]]')
    assert_equal 'box', p.dig('geoQ', 'geometry')
  end

  def test_ngsi_ld_watched_attributes_from_attrs
    p = payload('NGSI-LD', attrs: '["temperature","humidity"]')
    assert_equal %w[temperature humidity], p['watchedAttributes']
  end

  def test_ngsi_ld_omits_optional_fields_when_absent
    p = payload('NGSI-LD', alteration_types: [])
    assert_not p.key?('q')
    assert_not p.key?('geoQ')
    assert_not p.key?('watchedAttributes')
    assert_not p.key?('notificationTrigger')
    assert_not p.key?('expiresAt')
  end
end
