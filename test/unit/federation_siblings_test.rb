require File.expand_path('../../test_helper', __FILE__)

class FederationSiblingsTest < ActiveSupport::TestCase
  fixtures :projects, :trackers

  ENTITY_URN = 'urn:ngsi-ld:WasteContainer:042'.freeze

  def setup
    @connection = BrokerConnection.create!(
      name: 'Federation broker', standard: 'NGSI-LD',
      url: 'https://broker.example.com', fiware_service: 'shared',
      auth_mode: 'stored', auth_token: 'fed-token', token_header: 'X-Api-Key'
    )
  end

  def foreign_issue(instance, issue_id, status: 'open')
    {
      'id' => "urn:ngsi-ld:Issue:redmine:#{instance}:#{issue_id}",
      'type' => 'Issue',
      'title' => { 'type' => 'Property', 'value' => 'Container full' },
      'status' => { 'type' => 'Property', 'value' => status },
      'statusLabel' => { 'type' => 'Property', 'value' => 'In Progress' },
      'subtype' => { 'type' => 'Property', 'value' => 'WorkOrder' },
      'source' => { 'type' => 'Property', 'value' => "https://other.example/issues/#{issue_id}" }
    }
  end

  def stub_response(body, code: '200')
    response = Net::HTTPOK.new('1.1', code, 'OK')
    response.stubs(:body).returns(body.to_json)
    captured = nil
    Net::HTTP.any_instance.stubs(:request).with { |req| captured = req; true }.returns(response)
    -> { captured }
  end

  def siblings
    RedmineGttFiware::FederationSiblings.new(@connection).for_entity(ENTITY_URN)
  end

  def test_query_carries_context_auth_and_filters
    request = stub_response([foreign_issue('nexco-east', 7)])
    with_settings plugin_redmine_gtt_fiware: { 'fiware_instance_id' => 'city-shibuya' } do
      result = siblings
      assert_equal 1, result.size
      assert_equal 'nexco-east', result.first.org
      assert_equal 'WorkOrder', result.first.subtype
      assert result.first.open?
    end

    req = request.call
    assert_includes req.path, 'type=Issue'
    assert_includes req.path, Rack::Utils.escape(%(refersTo=="#{ENTITY_URN}"))
    assert_includes req['Link'], RedmineGttFiware::FederationSiblings::CONTEXT_URL
    assert_equal 'fed-token', req['X-Api-Key']
    assert_equal 'shared', req['NGSILD-Tenant']
  end

  # Own work orders are not siblings; entities without our URN shape count
  # as foreign (someone else works on it, whoever they are).
  def test_own_entities_are_filtered_out
    stub_response([
      foreign_issue('city-shibuya', 8),
      foreign_issue('nexco-east', 7),
      foreign_issue('nexco-east', 9).merge('id' => 'urn:ngsi-ld:Issue:handmade:1')
    ])
    with_settings plugin_redmine_gtt_fiware: { 'fiware_instance_id' => 'city-shibuya' } do
      result = siblings
      assert_equal %w[nexco-east external], result.map(&:org)
    end
  end

  # Broker data is untrusted: source is rendered as a link and embedded in
  # journal notes, so anything but plain http(s) is dropped at the boundary.
  def test_non_http_source_urls_are_dropped
    stub_response([
      foreign_issue('nexco-east', 7).merge('source' => { 'type' => 'Property', 'value' => 'javascript:alert(1)' }),
      foreign_issue('nexco-east', 8).merge('source' => { 'type' => 'Property', 'value' => 'not a url' })
    ])
    result = siblings
    assert_equal [nil, nil], result.map(&:source)
  end

  def test_broker_failure_degrades_to_empty
    Net::HTTP.any_instance.stubs(:request).raises(Errno::ECONNREFUSED)
    assert_equal [], siblings
  end

  def test_non_success_degrades_to_empty
    response = Net::HTTPForbidden.new('1.1', '403', 'Forbidden')
    response.stubs(:body).returns('denied')
    Net::HTTP.any_instance.stubs(:request).returns(response)
    assert_equal [], siblings
  end

  def test_blank_entity_urn_queries_nothing
    Net::HTTP.any_instance.stubs(:request).raises('must not be called')
    assert_equal [], RedmineGttFiware::FederationSiblings.new(@connection).for_entity('')
  end

  # The entity id comes from an untrusted notification payload and is
  # interpolated into the quoted q literal; an id that could break out of the
  # quotes or alter the query grammar must never reach the broker.
  def test_urn_with_query_grammar_characters_queries_nothing
    Net::HTTP.any_instance.stubs(:request).raises('must not be called')
    [
      %(urn:x";title!="),        # quote break-out
      'urn:x|urn:y',             # OR pattern
      'urn:x;attrs=*',           # statement separator
      "urn:x\nurn:y"             # header/newline smuggling
    ].each do |bad|
      assert_equal [], RedmineGttFiware::FederationSiblings.new(@connection).for_entity(bad),
                   "expected #{bad.inspect} to be rejected"
    end
  end
end
