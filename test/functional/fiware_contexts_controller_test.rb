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

  # The exposable standard terms are published for every instance: exposure
  # gates what is emitted, the vocabulary defines what the words mean.
  def test_context_carries_the_standard_terms
    get :show
    context = JSON.parse(response.body)['@context']
    RedmineGttFiware::InstanceContext::STANDARD_TERMS.each do |term|
      assert context.key?(term), "standard term #{term} must be defined"
    end
    # parent is a Relationship, so it expands as an IRI.
    assert_equal '@id', context.dig('parent', '@type')
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

  # Defense in depth for pre-validation rows: a stray reserved subtype must
  # never shadow a core term or prefix in the published document.
  def test_reserved_subtype_rows_cannot_shadow_core_terms
    legacy = EmissionMapping.new(broker_connection: @connection, tracker: Tracker.find(1), subtype: 'Issue')
    legacy.save!(validate: false)

    get :show
    body = JSON.parse(response.body)
    assert_equal 'gttfiware:Issue', body['@context']['Issue'], 'the core term must win'
  end

  # The same tracker mapped to the same subtype on several connections must
  # not repeat in the class label.
  def test_subtype_labels_dedupe_tracker_names
    other = BrokerConnection.create!(
      name: 'Second broker', standard: 'NGSI-LD',
      url: 'https://other.example.com', auth_mode: 'stored'
    )
    EmissionMapping.create!(broker_connection: @connection, tracker: Tracker.find(1), subtype: 'WorkOrder')
    EmissionMapping.create!(broker_connection: other, tracker: Tracker.find(1), subtype: 'WorkOrder')

    get :show
    label = JSON.parse(response.body)['@graph'].first['rdfs:label']
    assert_equal 1, label.scan(Tracker.find(1).name).size
  end

  # Exposed custom-field terms are published as instance vocabulary with a
  # labeled property node (#69, step 2c).
  def test_custom_field_terms_are_published
    custom_field = IssueCustomField.create!(name: 'Road surface', field_format: 'string',
                                            is_for_all: true, trackers: Tracker.all)
    mapping = EmissionMapping.create!(broker_connection: @connection, tracker: Tracker.find(1), subtype: 'WorkOrder')
    mapping.exposed_custom_fields = { custom_field.id => 'roadSurface' }
    mapping.save!

    get :show
    body = JSON.parse(response.body)
    assert_equal 'inst:roadSurface', body['@context']['roadSurface']
    node = body['@graph'].detect { |n| n['@id'] == 'inst:roadSurface' }
    assert_equal 'rdf:Property', node['@type']
    assert_includes node['rdfs:label'], 'Road surface'
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
