require File.expand_path('../../test_helper', __FILE__)

class EmissionMappingTest < ActiveSupport::TestCase
  fixtures :projects, :trackers

  def connection(overrides = {})
    BrokerConnection.create!(
      {
        name: "Emission broker #{SecureRandom.hex(3)}",
        standard: 'NGSI-LD',
        url: 'https://broker.example.com',
        auth_mode: 'stored'
      }.merge(overrides)
    )
  end

  def test_valid_with_ngsi_ld_connection
    mapping = EmissionMapping.new(broker_connection: connection, tracker: Tracker.first, subtype: 'WorkOrder')
    assert mapping.valid?
  end

  def test_subtype_must_be_a_json_ld_term
    ['', 'Work Order', '3D', 'ワークオーダー', 'work-order'].each do |bad|
      mapping = EmissionMapping.new(broker_connection: connection, tracker: Tracker.first, subtype: bad)
      assert_not mapping.valid?, "#{bad.inspect} must be rejected"
      assert mapping.errors[:subtype].present?
    end
  end

  def test_one_mapping_per_tracker_and_connection
    conn = connection
    EmissionMapping.create!(broker_connection: conn, tracker: Tracker.first, subtype: 'WorkOrder')
    duplicate = EmissionMapping.new(broker_connection: conn, tracker: Tracker.first, subtype: 'Incident')
    assert_not duplicate.valid?
    assert duplicate.errors[:tracker_id].present?
  end

  # Emission is NGSI-LD only in v1: the entity payload is JSON-LD.
  def test_rejects_an_ngsi_v2_connection
    mapping = EmissionMapping.new(broker_connection: connection(standard: 'NGSIv2'),
                                  tracker: Tracker.first, subtype: 'WorkOrder')
    assert_not mapping.valid?
    assert mapping.errors[:broker_connection].present?
  end

  # A subtype must not shadow core vocabulary terms or context prefixes in
  # the published document (#69 step 2), whatever the casing.
  def test_subtype_must_not_shadow_reserved_terms
    %w[Issue issue rdfs gttfiware inst location dateCreated type].each do |reserved|
      mapping = EmissionMapping.new(broker_connection: connection, tracker: Tracker.first, subtype: reserved)
      assert_not mapping.valid?, "#{reserved.inspect} must be rejected"
      assert mapping.errors[:subtype].present?
    end
  end

  # The exposure accessors trust nothing: unknown keys are dropped on read
  # and write, so IssueEntity can dispatch on every entry.
  def test_exposed_standard_fields_are_cleaned_against_the_catalog
    mapping = EmissionMapping.new(broker_connection: connection, tracker: Tracker.first, subtype: 'WorkOrder')
    mapping.exposed_standard_fields = ['priority', 'no_such_field', 'assignee']
    assert_equal %w[priority assignee], mapping.exposed_standard_fields

    mapping.exposed_attributes = { 'standard' => ['dueDate', 'bogus'] }
    assert_equal %w[dueDate], mapping.exposed_standard_fields

    mapping.exposed_attributes = nil
    assert_equal [], mapping.exposed_standard_fields
  end

  # A hand-edited or corrupted column value degrades to "nothing exposed"
  # instead of raising - the public context endpoint iterates every mapping.
  def test_corrupted_exposed_attributes_degrade_to_empty
    mapping = EmissionMapping.create!(broker_connection: connection, tracker: Tracker.first, subtype: 'WorkOrder')
    mapping.update_column(:exposed_attributes, 'not json {')
    assert_equal [], mapping.reload.exposed_standard_fields

    mapping.update_column(:exposed_attributes, '["an", "array"]')
    assert_equal [], mapping.reload.exposed_standard_fields
  end

  # --- custom field exposure (#69, step 2c) ----------------------------------

  def test_exposed_custom_fields_round_trip
    mapping = EmissionMapping.new(broker_connection: connection, tracker: Tracker.first, subtype: 'WorkOrder')
    mapping.exposed_custom_fields = { 5 => 'roadSurface', '7' => 'severityScore' }
    assert mapping.valid?
    assert_equal({ 5 => 'roadSurface', 7 => 'severityScore' }, mapping.exposed_custom_fields)
  end

  # An admin's typo must surface as an error, not vanish through the
  # reader's defensive filter.
  def test_invalid_custom_terms_are_validation_errors
    mapping = EmissionMapping.new(broker_connection: connection, tracker: Tracker.first, subtype: 'WorkOrder')
    ['road surface', 'title', 'rdf', '9lives'].each do |bad|
      mapping.exposed_custom_fields = { 5 => bad }
      assert_not mapping.valid?, "#{bad.inspect} must be rejected"
      # ... and the reader drops it regardless.
      assert_equal({}, mapping.exposed_custom_fields)
    end
  end

  # One inst: IRI must not be both a class and a property: custom terms may
  # not shadow any configured subtype, own mapping or another's.
  def test_custom_terms_must_not_shadow_subtypes
    conn = connection
    mapping = EmissionMapping.new(broker_connection: conn, tracker: Tracker.first, subtype: 'WorkOrder')
    mapping.exposed_custom_fields = { 5 => 'workorder' }
    assert_not mapping.valid?

    EmissionMapping.create!(broker_connection: conn, tracker: Tracker.first, subtype: 'Incident')
    other = EmissionMapping.new(broker_connection: conn, tracker: Tracker.all.second, subtype: 'WorkOrder')
    other.exposed_custom_fields = { 5 => 'incident' }
    assert_not other.valid?
  end

  def test_duplicate_custom_terms_are_rejected
    mapping = EmissionMapping.new(broker_connection: connection, tracker: Tracker.first, subtype: 'WorkOrder')
    mapping.exposed_custom_fields = { 5 => 'roadSurface', 7 => 'roadSurface' }
    assert_not mapping.valid?
  end

  def test_suggested_custom_term
    assert_equal 'reportedVia', EmissionMapping.suggested_custom_term(IssueCustomField.new(name: 'Reported via'))
    assert_equal 'onSiteVerified', EmissionMapping.suggested_custom_term(IssueCustomField.new(name: 'On-site verified'))
    fallback = EmissionMapping.suggested_custom_term(IssueCustomField.new(name: '調査日').tap { |cf| cf.id = 42 })
    assert_equal 'customField42', fallback
  end

  # The exposure catalog and the published vocabulary must not drift apart.
  def test_standard_fields_match_the_published_terms
    assert_equal RedmineGttFiware::InstanceContext::STANDARD_TERMS.sort,
                 EmissionMapping::STANDARD_FIELDS.keys.sort
  end

  # Every exposure switch publishes a task term in task mode (#152).
  def test_every_standard_field_has_a_task_term
    assert_equal EmissionMapping::STANDARD_FIELDS.keys.sort,
                 RedmineGttFiware::TaskEntity::TASK_TERMS.keys.sort
  end

  # --- task vocabulary (#152) ------------------------------------------------

  TASK_SETTINGS = { 'fiware_instance_id' => 'test-town', 'fiware_emission_vocabulary' => 'task' }.freeze

  # In task mode the instance terms sit on top of the task vocabulary's
  # context, so subtypes must not shadow its terms or types.
  def test_task_mode_rejects_subtypes_that_shadow_task_terms
    with_settings plugin_redmine_gtt_fiware: TASK_SETTINGS do
      %w[Task Project milestone Milestone name progress tm schema Issue
         end homepage identifier isPublic milestoneStatus projectStatus].each do |reserved|
        mapping = EmissionMapping.new(broker_connection: connection, tracker: Tracker.first, subtype: reserved)
        assert_not mapping.valid?, "#{reserved.inspect} must be rejected in task mode"
        assert mapping.errors[:subtype].present?
      end
    end
  end

  def test_task_mode_rejects_custom_terms_that_shadow_task_terms
    with_settings plugin_redmine_gtt_fiware: TASK_SETTINGS do
      mapping = EmissionMapping.new(broker_connection: connection, tracker: Tracker.first, subtype: 'WorkOrder')
      %w[due start estimatedDuration externalId keywords category title].each do |reserved|
        mapping.exposed_custom_fields = { 5 => reserved }
        assert_not mapping.valid?, "#{reserved.inspect} must be rejected in task mode"
        assert_equal({}, mapping.exposed_custom_fields)
      end
    end
  end

  # The GTT core is unchanged: task terms that are not GTT terms stay legal
  # there, so existing mappings keep validating.
  def test_gtt_mode_keeps_task_only_terms_legal
    project = EmissionMapping.new(broker_connection: connection, tracker: Tracker.first, subtype: 'Project')
    assert project.valid?

    mapping = EmissionMapping.new(broker_connection: connection, tracker: Tracker.first, subtype: 'WorkOrder')
    mapping.exposed_custom_fields = { 5 => 'due' }
    assert mapping.valid?
    assert_equal({ 5 => 'due' }, mapping.exposed_custom_fields)
  end

  # Tracker names are free text, often non-ASCII; the suggestion must always
  # be a usable term.
  def test_suggested_subtype
    assert_equal 'RoadDamage', EmissionMapping.suggested_subtype(Tracker.new(name: 'road damage'))
    assert_equal 'Bug', EmissionMapping.suggested_subtype(Tracker.new(name: 'Bug'))
    assert_equal 'WorkOrder', EmissionMapping.suggested_subtype(Tracker.new(name: '障害'))
  end
end
