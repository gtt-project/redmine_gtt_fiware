require File.expand_path('../../test_helper', __FILE__)

class BrokerConnectionTest < ActiveSupport::TestCase
  fixtures :projects, :trackers, :issue_statuses, :users, :members,
           :member_roles, :roles, :enumerations

  def connection(overrides = {})
    BrokerConnection.new(
      {
        name: 'City broker',
        standard: 'NGSI-LD',
        url: 'https://broker.example.com',
        auth_mode: 'stored'
      }.merge(overrides)
    )
  end

  def test_valid_with_minimal_attributes
    assert connection.valid?
  end

  def test_requires_name_url_and_known_standard
    assert_not connection(name: '').valid?
    assert_not connection(url: '').valid?
    assert_not connection(standard: 'NGSIv3').valid?
    assert connection(standard: 'NGSIv2').valid?
  end

  def test_name_must_be_unique
    connection.save!
    duplicate = connection
    assert_not duplicate.valid?
    assert duplicate.errors[:name].any?
  ensure
    BrokerConnection.delete_all
  end

  def test_rejects_non_http_urls
    assert_not connection(url: 'ftp://broker.example.com').valid?
    assert_not connection(url: 'not a url').valid?
    assert connection(url: 'http://localhost:1026').valid?
  end

  def test_auth_mode_must_be_known
    assert connection(auth_mode: 'browser').valid?
    assert_not connection(auth_mode: 'keychain').valid?
  end

  # #37: tenant header values are validated so publishing does not fail with
  # opaque broker errors.
  def test_validates_fiware_service
    assert connection(fiware_service: 'smartcity_01').valid?
    assert connection(fiware_service: nil).valid?
    assert_not connection(fiware_service: "smart'city").valid?
    assert_not connection(fiware_service: 'a' * 51).valid?
  end

  def test_validates_fiware_servicepath
    assert connection(fiware_servicepath: '/roads/lighting').valid?
    assert connection(fiware_servicepath: nil).valid?
    assert_not connection(fiware_servicepath: 'roads').valid?
    assert_not connection(fiware_servicepath: '/ro ads').valid?
    assert_not connection(fiware_servicepath: '/' + Array.new(11, 'x').join('/')).valid?
  end

  # The token round-trips through Redmine::Ciphering: with a database_cipher_key
  # configured the stored column holds ciphertext, without one it falls back to
  # plaintext, and the reader returns the original value either way.
  def test_auth_token_is_ciphered_and_round_trips
    c = connection
    c.auth_token = 'broker-token-123'
    assert_equal 'broker-token-123', c.auth_token
    if Redmine::Configuration['database_cipher_key'].present?
      assert_not_equal 'broker-token-123', c.read_attribute(:auth_token)
      assert c.read_attribute(:auth_token).start_with?('aes-256-cbc:')
    else
      assert_equal 'broker-token-123', c.read_attribute(:auth_token)
    end
  end

  def test_stored_auth_predicate
    assert connection(auth_mode: 'stored').stored_auth?
    assert_not connection(auth_mode: 'browser').stored_auth?
  end

  def test_ngsi_ld_predicate
    assert connection(standard: 'NGSI-LD').ngsi_ld?
    assert_not connection(standard: 'NGSIv2').ngsi_ld?
  end

  def test_cannot_be_destroyed_while_templates_reference_it
    c = connection(context: 'https://broker.example.com/context.jsonld')
    c.save!
    template = SubscriptionTemplate.create!(
      status: 'active',
      name: 'Uses connection',
      subject: 'S ${id}',
      description: 'D',
      entities_string: '[{"idPattern": ".*", "type": "T"}]',
      project_id: 1,
      tracker_id: 1,
      issue_status_id: 1,
      issue_priority_id: IssuePriority.first.id,
      member_id: 1,
      broker_connection_id: c.id
    )
    assert_not c.destroy
    assert c.errors[:base].any?
    template.destroy
    assert c.destroy
  ensure
    BrokerConnection.delete_all
  end
end
