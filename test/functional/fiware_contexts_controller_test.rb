require File.expand_path('../../test_helper', __FILE__)

class FiwareContextsControllerTest < ActionController::TestCase
  fixtures :projects, :trackers

  def setup
    @connection = BrokerConnection.create!(
      name: 'Context broker', standard: 'NGSI-LD',
      url: 'https://broker.example.com', auth_mode: 'stored'
    )
  end

  # Brokers dereference @context at ingestion; the document must be readable
  # without any session or credential.
  def test_context_is_public
    @request.session[:user_id] = nil
    with_settings login_required: '1' do
      get :show
      assert_response :success
      assert_equal 'application/ld+json', response.media_type
    end
  end

  def test_context_carries_the_core_terms
    get :show
    context = JSON.parse(response.body)['@context']
    RedmineGttFiware::InstanceContext::CORE_TERMS.each do |term|
      assert context.key?(term), "core term #{term} must be defined"
    end
    # refersTo expands as an IRI, not a string.
    assert_equal '@id', context.dig('refersTo', '@type')
  end

  def test_subtypes_are_declared_subclasses_of_issue
    EmissionMapping.create!(broker_connection: @connection, tracker: Tracker.find(1), subtype: 'WorkOrder')
    EmissionMapping.create!(broker_connection: @connection, tracker: Tracker.find(2), subtype: 'WorkOrder')
    EmissionMapping.create!(broker_connection: @connection, tracker: Tracker.find(3), subtype: 'Incident')

    get :show
    body = JSON.parse(response.body)
    assert_equal 'inst:WorkOrder', body['@context']['WorkOrder']

    classes = body['@graph'].index_by { |node| node['@id'] }
    assert_equal 2, classes.size, 'one class per distinct subtype'
    work_order = classes['inst:WorkOrder']
    assert_equal 'gttfiware:Issue', work_order.dig('rdfs:subClassOf', '@id')
    # The label names every mapped tracker.
    assert_includes work_order['rdfs:label'], Tracker.find(1).name
    assert_includes work_order['rdfs:label'], Tracker.find(2).name
  end

  # The configured public host defines the instance namespace (#101
  # semantics); the request host is only the local fallback.
  def test_instance_namespace_follows_the_configured_host
    with_settings host_name: 'redmine.public.example', protocol: 'https' do
      get :show
      body = JSON.parse(response.body)
      assert_equal 'https://redmine.public.example/fiware/vocab#', body['@context']['inst']
    end

    with_settings host_name: '' do
      get :show
      body = JSON.parse(response.body)
      assert_equal 'http://test.host/fiware/vocab#', body['@context']['inst']
    end
  end
end
