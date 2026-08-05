require File.expand_path('../../test_helper', __FILE__)

class SubscriptionTemplateTest < ActiveSupport::TestCase
  fixtures :projects, :trackers, :issue_statuses, :users, :members,
           :member_roles, :roles, :enumerations, :issue_categories, :versions

  def broker_connection(attributes = {})
    @broker_connection ||= BrokerConnection.create!(
      {
        name: 'Test broker',
        standard: 'NGSIv2',
        url: 'https://broker.example.com',
        auth_mode: 'browser'
      }.merge(attributes)
    )
  end

  def valid_attributes(overrides = {})
    {
      broker_connection_id: broker_connection.id,
      status: 'active',
      name: 'Temperature alerts',
      subject: 'Sensor ${id}',
      description: 'A monitored value changed',
      entities_string: '[{"idPattern": ".*", "type": "TemperatureSensor"}]',
      project_id: 1,
      tracker_id: 1,
      issue_status_id: 1,
      member_id: 1,
    }.merge(overrides)
  end

  def test_valid_template_saves
    template = SubscriptionTemplate.new(valid_attributes)
    assert template.valid?, template.errors.full_messages.join(', ')
    assert template.save
  end

  # #103: a tracker that disables a core field must not keep a stored value
  # for it - the form hides the selects, but hidden inputs still submit.
  def test_save_clears_fields_the_tracker_disables
    tracker = Tracker.find(1)
    tracker.core_fields = Tracker::CORE_FIELDS - %w[category_id fixed_version_id priority_id]
    tracker.save!
    category = IssueCategory.create!(project_id: 1, name: 'Field test')
    version = Version.create!(project_id: 1, name: 'Field test 1.0')

    template = SubscriptionTemplate.create!(valid_attributes(
      issue_category_id: category.id,
      version_id: version.id,
      issue_priority_id: IssuePriority.first.id
    ))
    assert_nil template.issue_category_id
    assert_nil template.version_id
    assert_nil template.issue_priority_id
  end

  def test_save_keeps_fields_the_tracker_allows
    category = IssueCategory.create!(project_id: 1, name: 'Field test')
    template = SubscriptionTemplate.create!(valid_attributes(issue_category_id: category.id))
    assert_equal category.id, template.issue_category_id
  end

  # --- custom field templates (#103, phase 2) -----------------------------

  def issue_custom_field(attributes = {})
    IssueCustomField.create!({
      name: "Severity #{SecureRandom.hex(3)}",
      field_format: 'string',
      is_for_all: true,
      trackers: [Tracker.find(1)]
    }.merge(attributes))
  end

  def test_custom_field_values_round_trip_and_drop_blanks
    field = issue_custom_field
    template = SubscriptionTemplate.create!(valid_attributes(
      issue_custom_field_values: { field.id.to_s => '${severity}', '999999' => '   ' }
    ))
    assert_equal({ field.id.to_s => '${severity}' }, template.reload.issue_custom_field_values)
  end

  def test_custom_field_values_for_other_trackers_are_cleared_on_save
    foreign_field = issue_custom_field(trackers: [Tracker.find(2)])
    template = SubscriptionTemplate.create!(valid_attributes(
      issue_custom_field_values: { foreign_field.id.to_s => '${severity}' }
    ))
    assert_equal({}, template.reload.issue_custom_field_values)
  end

  def test_custom_field_values_read_as_empty_hash_when_malformed
    template = SubscriptionTemplate.create!(valid_attributes)
    template.update_column(:issue_custom_field_values, 'not json')
    assert_equal({}, template.reload.issue_custom_field_values)
  end

  # A new subscription must be creatable from the visible fields alone
  # (#102): the required status select otherwise starts blank.
  def test_default_status_is_active
    assert_equal 'active', SubscriptionTemplate.new.status
  end

  def test_default_alteration_types
    template = SubscriptionTemplate.new
    assert_equal ['entityCreate', 'entityChange'], template.alteration_types
  end

  def test_default_notify_on_metadata_change
    template = SubscriptionTemplate.new
    assert_equal true, template.notify_on_metadata_change
  end

  def test_explicit_false_notify_on_metadata_change_is_respected
    template = SubscriptionTemplate.new(valid_attributes(notify_on_metadata_change: false))
    assert_equal false, template.notify_on_metadata_change
  end

  def test_name_is_required
    template = SubscriptionTemplate.new(valid_attributes(name: nil))
    assert_not template.valid?
    assert template.errors.added?(:name, :blank)
  end

  # Broker configuration lives on the connection since #67; a template cannot
  # exist without one.
  def test_broker_connection_is_required
    template = SubscriptionTemplate.new(valid_attributes(broker_connection_id: nil))
    assert_not template.valid?
    assert template.errors[:broker_connection].present?
  end

  def test_delegates_broker_fields_to_the_connection
    template = SubscriptionTemplate.new(valid_attributes)
    assert_equal 'NGSIv2', template.standard
    assert_equal 'https://broker.example.com', template.broker_url
    assert_not template.ngsi_ld?
  end

  # An LD template needs an @context: its own value or the connection default.
  def test_effective_context_falls_back_to_the_connection
    ld_connection = BrokerConnection.create!(
      name: 'LD broker', standard: 'NGSI-LD', url: 'https://ld.example.com',
      context: 'https://ld.example.com/default-context.jsonld', auth_mode: 'browser'
    )
    template = SubscriptionTemplate.new(valid_attributes(broker_connection_id: ld_connection.id))
    assert template.valid?, template.errors.full_messages.join(', ')
    assert_equal 'https://ld.example.com/default-context.jsonld', template.effective_context

    template.context = 'https://example.test/override.jsonld'
    assert_equal 'https://example.test/override.jsonld', template.effective_context
  end

  # #95: template overrides connection, connection overrides the default.
  # 0 means "no throttling" and must not be treated as unset.
  def test_effective_throttling_precedence
    template = SubscriptionTemplate.new(valid_attributes)
    assert_equal BrokerConnection::DEFAULT_THROTTLING, template.effective_throttling

    template.broker_connection.throttling = 30
    assert_equal 30, template.effective_throttling

    template.throttling = 5
    assert_equal 5, template.effective_throttling

    template.throttling = 0
    assert_equal 0, template.effective_throttling
  end

  def test_throttling_must_be_a_non_negative_integer
    assert SubscriptionTemplate.new(valid_attributes(throttling: nil)).valid?
    assert SubscriptionTemplate.new(valid_attributes(throttling: 0)).valid?
    assert SubscriptionTemplate.new(valid_attributes(throttling: 60)).valid?
    invalid = SubscriptionTemplate.new(valid_attributes(throttling: -5))
    assert_not invalid.valid?
    assert invalid.errors[:throttling].present?
  end

  def test_ld_template_requires_an_effective_context
    ld_connection = BrokerConnection.create!(
      name: 'LD broker no context', standard: 'NGSI-LD', url: 'https://ld.example.com', auth_mode: 'browser'
    )
    template = SubscriptionTemplate.new(valid_attributes(broker_connection_id: ld_connection.id))
    assert_not template.valid?
    assert template.errors[:effective_context].present?

    template.context = 'https://example.test/context.jsonld'
    assert template.valid?, template.errors.full_messages.join(', ')
  end

  # A template saved without alteration types must stay valid across later
  # updates (e.g. storing the broker's subscription id after publish).
  # Regression: the inclusion validation used to reject the stored empty
  # state on persisted records, silently breaking the publish flow.
  def test_persisted_template_without_alteration_types_stays_updatable
    template = SubscriptionTemplate.create!(valid_attributes(alteration_types: []))
    reloaded = SubscriptionTemplate.find(template.id)
    assert_equal [], reloaded.alteration_types
    # And the just-saved in-memory instance is usable without a reload: the
    # old hand-rolled before_save serialization left a JSON string behind
    # that failed revalidation until the record was reloaded.
    assert template.valid?, template.errors.full_messages.join(', ')
    assert reloaded.update(subscription_id: 'sub-1'), reloaded.errors.full_messages.join(', ')
  end

  def test_bogus_alteration_types_are_rejected
    template = SubscriptionTemplate.new(valid_attributes(alteration_types: ['bogus']))
    assert_not template.valid?
    assert template.errors[:alteration_types].present?
  end

  def test_status_must_be_valid
    template = SubscriptionTemplate.new(valid_attributes(status: 'paused'))
    assert_not template.valid?
    assert template.errors[:status].present?
  end

  def test_entities_string_must_be_valid_json
    template = SubscriptionTemplate.new(valid_attributes(entities_string: 'not json'))
    assert_not template.valid?
    assert template.errors[:entities_string].present?
  end

  # Blank input is the presence validation's job: exactly one error, and no
  # TypeError from JSON.parse(nil).
  def test_blank_entities_string_reports_presence_only
    ['', nil].each do |blank|
      template = SubscriptionTemplate.new(valid_attributes(entities_string: blank))
      template.entities = nil
      assert_not template.valid?
      assert_equal 1, template.errors[:entities_string].size, "#{blank.inspect} must add exactly one error"
    end
  end

  # Parsable JSON with the wrong shape must fail validation too: the
  # subscription builders expect a non-empty array of entity objects.
  def test_entities_string_must_be_a_non_empty_array_of_objects
    ['{}', '[]', '[1, 2]', '"TemperatureSensor"', '[{"type": "X"}, "y"]'].each do |bad|
      template = SubscriptionTemplate.new(valid_attributes(entities_string: bad))
      assert_not template.valid?, "#{bad.inspect} must be rejected"
      assert template.errors[:entities_string].present?
    end
  end

  def test_entities_string_accepts_id_and_id_pattern_entries
    good = '[{"type": "RoadDamage", "idPattern": ".*"}, {"type": "RoadDamage", "id": "urn:x"}]'
    template = SubscriptionTemplate.new(valid_attributes(entities_string: good))
    assert template.valid?
    assert_equal 2, template.entities.size
  end

  # 'null' is what the picker serializes with no rows: it clears the stored
  # attachments instead of failing validation.
  def test_attachments_string_null_clears_attachments
    template = SubscriptionTemplate.create!(
      valid_attributes(attachments_string: '[{"url": "https://example.com/a.jpg"}]')
    )
    assert_equal 1, template.attachments.size

    template.attachments_string = 'null'
    assert template.valid?
    template.save!
    assert_nil template.reload.attachments
  end

  def test_attachments_string_must_be_an_array_of_objects
    ['not json', '{}', '[1]', '"https://example.com/a.jpg"', '[{"url": "x"}, 5]'].each do |bad|
      template = SubscriptionTemplate.new(valid_attributes(attachments_string: bad))
      assert_not template.valid?, "#{bad.inspect} must be rejected"
      assert template.errors[:attachments_string].present?
    end
  end

  def test_attachments_string_accepts_an_array_of_objects
    template = SubscriptionTemplate.new(
      valid_attributes(attachments_string: '[{"url": "https://example.com/a.jpg", "filename": "a-${id}.jpg"}]')
    )
    assert template.valid?
    assert_equal 'a-${id}.jpg', template.attachments.first['filename']
  end

  # geometry_string stays free-form JSON: "${location}" (a string template),
  # a GeoJSON object and 'null' (clear) are all legitimate values.
  def test_geometry_string_accepts_template_geojson_and_null
    ['"${location}"', '{"type": "Point", "coordinates": [1, 2]}', 'null'].each do |good|
      template = SubscriptionTemplate.new(valid_attributes(geometry_string: good))
      assert template.valid?, "#{good.inspect} must be accepted"
    end
    template = SubscriptionTemplate.new(valid_attributes(geometry_string: '{not json'))
    assert_not template.valid?
    assert template.errors[:geometry_string].present?
  end

  def test_attrs_must_be_a_json_array_of_strings
    ['["temperature", "humidity"]', '', nil].each do |good|
      template = SubscriptionTemplate.new(valid_attributes(attrs: good))
      assert template.valid?, "#{good.inspect} must be accepted"
    end
    ['[1]', '"temperature"', '{"a": 1}', 'not json'].each do |bad|
      template = SubscriptionTemplate.new(valid_attributes(attrs: bad))
      assert_not template.valid?, "#{bad.inspect} must be rejected"
      assert template.errors[:attrs].present?
    end
  end

  def test_name_is_unique_within_project
    SubscriptionTemplate.create!(valid_attributes)
    duplicate = SubscriptionTemplate.new(valid_attributes)
    assert_not duplicate.valid?
    assert duplicate.errors[:name].present?
  end

  def test_threshold_create_hours_converts_to_seconds
    template = SubscriptionTemplate.new(valid_attributes)
    template.threshold_create_hours = 2
    assert_equal 7200, template.threshold_create
    assert_equal 2, template.threshold_create_hours
  end

  def test_geo_query_fields_must_be_all_or_none
    template = SubscriptionTemplate.new(valid_attributes(expression_georel: 'near;maxDistance:1000'))
    assert_not template.valid?
    assert template.errors[:base].present?
  end

  def test_generates_a_webhook_secret_on_create
    template = SubscriptionTemplate.create!(valid_attributes)
    assert_not_nil template.webhook_secret
    assert_equal 64, template.webhook_secret.length # SecureRandom.hex(32)
  end

  def test_ensure_webhook_secret_keeps_an_existing_secret
    template = SubscriptionTemplate.create!(valid_attributes)
    original = template.webhook_secret
    template.ensure_webhook_secret!
    assert_equal original, template.reload.webhook_secret
  end

  def test_ensure_webhook_secret_backfills_a_blank_secret
    template = SubscriptionTemplate.create!(valid_attributes)
    template.update_column(:webhook_secret, nil)
    template.ensure_webhook_secret!
    assert_not_nil template.reload.webhook_secret
    assert_equal 64, template.webhook_secret.length
  end

  def test_valid_webhook_secret_matches_only_the_stored_secret
    template = SubscriptionTemplate.create!(valid_attributes)
    assert template.valid_webhook_secret?(template.webhook_secret)
    assert_not template.valid_webhook_secret?('wrong')
    assert_not template.valid_webhook_secret?('')
    assert_not template.valid_webhook_secret?(nil)
  end

  def test_valid_webhook_secret_is_false_when_no_secret_is_stored
    template = SubscriptionTemplate.new(valid_attributes)
    template.webhook_secret = nil
    assert_not template.valid_webhook_secret?('anything')
    assert_not template.valid_webhook_secret?(nil)
  end

  # --- project scoping -------------------------------------------------------
  # The member is the sharpest edge: the webhook acts as the member's user,
  # so a foreign member_id would author issues as a user from an unrelated
  # project. Category and version follow core's Issue scoping.

  def test_member_must_belong_to_the_project
    foreign_member = Member.where.not(project_id: 1).first
    template = SubscriptionTemplate.new(valid_attributes(member_id: foreign_member.id))
    assert_not template.valid?
    assert template.errors[:member].any?
  end

  def test_issue_category_must_belong_to_the_project
    foreign_category = IssueCategory.where.not(project_id: 1).first
    template = SubscriptionTemplate.new(valid_attributes(issue_category_id: foreign_category.id))
    assert_not template.valid?
    assert template.errors[:issue_category].any?
  end

  def test_version_must_be_available_to_the_project
    foreign_version = Version.where.not(project_id: 1).where(sharing: 'none').first
    template = SubscriptionTemplate.new(valid_attributes(version_id: foreign_version.id))
    assert_not template.valid?
    assert template.errors[:version].any?
  end

  def test_own_project_associations_are_accepted
    category = IssueCategory.find_by(project_id: 1)
    version = Version.find_by(project_id: 1)
    template = SubscriptionTemplate.new(
      valid_attributes(issue_category_id: category.id, version_id: version.id)
    )
    assert template.valid?, template.errors.full_messages.join(', ')
  end
end
