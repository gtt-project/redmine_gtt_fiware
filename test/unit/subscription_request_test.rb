require File.expand_path('../../test_helper', __FILE__)

class SubscriptionRequestTest < ActiveSupport::TestCase
  BASE_URL = 'https://redmine.example.com'.freeze

  # Builds an unsaved template + connection (no DB writes) with sensible
  # defaults for the given standard; overrides win. Broker-level overrides
  # (broker_url, fiware_service, fiware_servicepath) land on the connection.
  def template(standard, overrides = {})
    connection = BrokerConnection.new(
      name: 'Test broker',
      standard: standard,
      url: overrides.delete(:broker_url) || 'https://broker.example.com',
      fiware_service: overrides.delete(:fiware_service),
      fiware_servicepath: overrides.delete(:fiware_servicepath),
      auth_mode: 'browser'
    )
    t = SubscriptionTemplate.new(
      {
        status: 'active',
        name: 'Temperature alerts',
        subject: 'Sensor ${id}',
        description: 'changed',
        context: 'https://uri.etsi.org/ngsi-ld/v1/ngsi-ld-core-context.jsonld'
      }.merge(overrides)
    )
    t.broker_connection = connection
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

  # A broker mounted under a path prefix without a version segment gets the
  # default prefix appended to its path, not substituted for it. Absolute-path
  # URI merging used to drop the prefix and target the wrong URL.
  def test_ngsi_ld_appends_the_prefix_to_a_broker_path_without_a_version
    req = build('NGSI-LD', broker_url: 'https://broker.example.com/context-broker')
    assert_equal 'https://broker.example.com/context-broker/ngsi-ld/v1/subscriptions', req.subscriptions_url
  end

  def test_ngsi_v2_appends_the_prefix_to_a_broker_path_without_a_version
    req = build('NGSIv2', broker_url: 'https://broker.example.com/orion')
    assert_equal 'https://broker.example.com/orion/v2/subscriptions', req.subscriptions_url
  end

  # /v2 without a minor version is the common spelling and counts as an
  # explicit versioned path (it used to be unrecognized, which both doubled
  # the version segment and dropped any prefix before it).
  def test_ngsi_v2_recognizes_a_plain_v2_path
    req = build('NGSIv2', broker_url: 'https://broker.example.com/orion/v2')
    assert_equal 'https://broker.example.com/orion/v2/subscriptions', req.subscriptions_url
  end

  # --- NGSIv2 payload -------------------------------------------------------

  def test_ngsi_v2_payload_shape
    p = payload('NGSIv2', alteration_types: %w[entityCreate entityChange])
    assert_equal [{ 'idPattern' => '.*', 'type' => 'TemperatureSensor' }], p.dig('subject', 'entities')
    assert_equal %w[entityCreate entityChange], p.dig('subject', 'condition', 'alterationTypes')
    assert_equal 3, p['throttling']
    assert_equal 'active', p['status']
  end

  # The description is the template name with only Orion's forbidden
  # characters removed: readable on the broker, and non-ASCII (Japanese
  # names) untouched. It used to be URL-encoded wholesale.
  def test_ngsi_v2_description_strips_only_orion_forbidden_characters
    p = payload('NGSIv2', name: %(Road damage (Aoyama) <test> "quoted" 道路損傷))
    assert_equal 'Road damage Aoyama test quoted 道路損傷', p['description']
  end

  def test_ngsi_ld_description_is_the_name_verbatim
    p = payload('NGSI-LD', name: 'Road damage (Aoyama)')
    assert_equal 'Road damage (Aoyama)', p['description']
  end

  # Setting.host_name may carry a sub-URI path ("example.com/redmine"); the
  # callback URLs must keep it instead of joining it away (#101).
  def test_callback_urls_preserve_a_sub_uri_base
    builder = RedmineGttFiware::SubscriptionRequest.build(
      template('NGSIv2'), base_url: 'https://example.com/redmine', throttling: 3
    )
    http_custom = JSON.parse(builder.to_json).dig('notification', 'httpCustom')
    assert_equal 'https://example.com/redmine/fiware/subscription_template/123/notification',
                 http_custom['url']

    # A trailing slash on the base must not produce a double slash.
    builder = RedmineGttFiware::SubscriptionRequest.build(
      template('NGSIv2'), base_url: 'https://example.com/redmine/', throttling: 3
    )
    http_custom = JSON.parse(builder.to_json).dig('notification', 'httpCustom')
    assert_equal 'https://example.com/redmine/fiware/subscription_template/123/notification',
                 http_custom['url']
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

  # The stored geo triple uses NGSIv2 syntax (the Area picker writes
  # coveredBy + "lat,lon;..." pairs). NGSI-LD has no coveredBy (within is
  # the equivalent), near modifiers use ==, and coordinates are a GeoJSON
  # array in lon,lat order; the builder translates.
  def test_ngsi_ld_translates_a_v2_style_boundary_triple
    p = payload('NGSI-LD',
                expression_georel: 'coveredBy',
                expression_geometry: 'polygon',
                expression_coords: '35.0,135.0;35.0,136.0;36.0,136.0;35.0,135.0')
    geo_q = p['geoQ']
    assert_equal 'within', geo_q['georel']
    assert_equal 'Polygon', geo_q['geometry']
    assert_equal [[[135.0, 35.0], [136.0, 35.0], [136.0, 36.0], [135.0, 35.0]]],
                 geo_q['coordinates']
  end

  def test_ngsi_ld_translates_a_v2_style_near_point
    p = payload('NGSI-LD',
                expression_georel: 'near;maxDistance:2000',
                expression_geometry: 'point',
                expression_coords: '35.68,139.69')
    geo_q = p['geoQ']
    assert_equal 'near;maxDistance==2000', geo_q['georel']
    assert_equal [139.69, 35.68], geo_q['coordinates']
  end

  # The same stored triple stays untouched for NGSIv2 (Orion wants exactly
  # this syntax).
  def test_ngsi_v2_keeps_the_boundary_triple_verbatim
    p = payload('NGSIv2',
                expression_georel: 'coveredBy',
                expression_geometry: 'polygon',
                expression_coords: '35.0,135.0;35.0,136.0;36.0,136.0;35.0,135.0')
    expression = p.dig('subject', 'condition', 'expression')
    assert_equal 'coveredBy', expression['georel']
    assert_equal '35.0,135.0;35.0,136.0;36.0,136.0;35.0,135.0', expression['coords']
  end

  # Expiry must be an ISO 8601 UTC timestamp in both standards; a raw
  # TimeWithZone serialized through JSON.generate is "2026-01-01 00:00:00
  # +0900", which brokers reject.
  def test_expires_is_iso8601_utc_in_both_standards
    time = Time.utc(2027, 1, 2, 3, 4, 5)
    assert_equal '2027-01-02T03:04:05Z', payload('NGSIv2', expires: time)['expires']
    assert_equal '2027-01-02T03:04:05Z', payload('NGSI-LD', expires: time)['expiresAt']
  end

  # CIM 009 requires throttling > 0; "no throttling" (0) is expressed by
  # omitting the field. NGSIv2/Orion accepts 0.
  def test_ngsi_ld_omits_zero_throttling
    builder = RedmineGttFiware::SubscriptionRequest.build(template('NGSI-LD'), base_url: BASE_URL, throttling: 0)
    assert_not JSON.parse(builder.to_json).key?('throttling')
    assert_equal 0, JSON.parse(RedmineGttFiware::SubscriptionRequest.build(template('NGSIv2'), base_url: BASE_URL, throttling: 0).to_json)['throttling']
  end

  # NGSIv2 subscription ids are broker-assigned; Orion rejects a
  # client-supplied id on POST. NGSI-LD allows one.
  def test_only_ngsi_ld_carries_a_client_supplied_id
    v2 = payload('NGSIv2', subscription_id: 'sub-1')
    assert_not v2.key?('id')
    ld = payload('NGSI-LD', subscription_id: 'urn:ngsi-ld:Subscription:1')
    assert_equal 'urn:ngsi-ld:Subscription:1', ld['id']
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

  # --- tenant headers / content type ---------------------------------------

  def test_content_type_per_standard
    assert_equal 'application/json', build('NGSIv2').content_type
    assert_equal 'application/ld+json', build('NGSI-LD').content_type
  end

  def test_ngsi_v2_tenant_headers
    req = build('NGSIv2', fiware_service: 'smartcity', fiware_servicepath: '/roads')
    assert_equal({ 'Fiware-Service' => 'smartcity', 'Fiware-ServicePath' => '/roads' }, req.tenant_headers)
  end

  def test_ngsi_ld_tenant_headers_use_ngsild_tenant
    req = build('NGSI-LD', fiware_service: 'smartcity')
    assert_equal({ 'NGSILD-Tenant' => 'smartcity' }, req.tenant_headers)
  end

  def test_tenant_headers_empty_without_a_service
    assert_equal({}, build('NGSIv2').tenant_headers)
  end

  # The template's own context overrides the connection's default.
  def test_ngsi_ld_context_falls_back_to_the_connection_default
    req = build('NGSI-LD', context: nil)
    req_template = req.instance_variable_get(:@template)
    req_template.broker_connection.context = 'https://conn.example.test/ctx.jsonld'
    assert_equal 'https://conn.example.test/ctx.jsonld', JSON.parse(req.to_json)['@context']
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
