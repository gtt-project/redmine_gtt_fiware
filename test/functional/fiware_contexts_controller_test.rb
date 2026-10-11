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
      get :task_context
      assert_response :success
      assert_equal 'application/ld+json', response.media_type
    end
  end

  # The task terms come from the redmine subject of GTT's node, imported
  # first; the inline object adds only instance terms under the instance
  # namespace.
  def test_context_imports_the_gtt_task_extension
    with_settings host_name: 'redmine.public.example', protocol: 'https' do
      get :task_context
    end
    context = JSON.parse(response.body)['@context']
    assert_kind_of Array, context
    assert_equal 'https://models.gtt-project.org/context/redmine/v0.jsonld', context.first
    inline = context.last
    assert_equal 'https://redmine.public.example/fiware/vocab#', inline['inst']
    # Only prefixes and instance terms are defined inline.
    assert_equal %w[inst rdf rdfs], inline.keys.sort
  end

  def test_subtypes_are_declared_subclasses_of_task
    EmissionMapping.create!(broker_connection: @connection, tracker: Tracker.find(1), subtype: 'WorkOrder')
    EmissionMapping.create!(broker_connection: @connection, tracker: Tracker.find(2), subtype: 'WorkOrder')
    EmissionMapping.create!(broker_connection: @connection, tracker: Tracker.find(3), subtype: 'Incident')

    get :task_context
    body = JSON.parse(response.body)
    assert_equal 'inst:WorkOrder', body['@context'].last['WorkOrder']

    classes = body['@graph'].index_by { |node| node['@id'] }
    assert_equal 2, classes.size, 'one class per distinct subtype'
    work_order = classes['inst:WorkOrder']
    assert_equal 'https://datamodels.jp/ns/task/Task', work_order.dig('rdfs:subClassOf', '@id')
    # The label names every mapped tracker.
    assert_includes work_order['rdfs:label'], Tracker.find(1).name
    assert_includes work_order['rdfs:label'], Tracker.find(2).name
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

    get :task_context
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

    get :task_context
    body = JSON.parse(response.body)
    assert_equal 'inst:roadSurface', body['@context'].last['roadSurface']
    node = body['@graph'].detect { |n| n['@id'] == 'inst:roadSurface' }
    assert_equal 'rdf:Property', node['@type']
    assert_includes node['rdfs:label'], 'Road surface'
  end

  # Defense in depth for rows saved before the task terms were reserved: the
  # published context never redefines a task term.
  def test_reserved_rows_cannot_redefine_task_terms
    custom_field = IssueCustomField.create!(name: 'Deadline note', field_format: 'string',
                                            is_for_all: true, trackers: Tracker.all)
    mapping = EmissionMapping.new(broker_connection: @connection, tracker: Tracker.find(1), subtype: 'Project')
    mapping.exposed_attributes = { 'custom' => { custom_field.id.to_s => 'due' } }
    mapping.save!(validate: false)
    # Issue is the redmine subject's name for the emitted type.
    EmissionMapping.new(broker_connection: @connection, tracker: Tracker.find(2), subtype: 'Issue')
                   .save!(validate: false)

    get :task_context
    inline = JSON.parse(response.body)['@context'].last
    assert_not inline.key?('Project')
    assert_not inline.key?('due')
    assert_not inline.key?('Issue')
  end

  # The configured public host defines the instance namespace (#101
  # semantics); the request host is only the local fallback.
  def test_instance_namespace_follows_the_configured_host
    with_settings host_name: 'redmine.public.example', protocol: 'https' do
      get :task_context
      body = JSON.parse(response.body)
      assert_equal 'https://redmine.public.example/fiware/vocab#', body['@context'].last['inst']
    end

    with_settings host_name: '' do
      get :task_context
      body = JSON.parse(response.body)
      assert_equal 'http://test.host/fiware/vocab#', body['@context'].last['inst']
    end
  end
end
