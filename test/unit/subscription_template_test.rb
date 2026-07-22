require File.expand_path('../../test_helper', __FILE__)

class SubscriptionTemplateTest < ActiveSupport::TestCase
  fixtures :projects, :trackers, :issue_statuses, :users, :members,
           :member_roles, :roles, :enumerations

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
end
