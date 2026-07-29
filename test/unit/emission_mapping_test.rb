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

  # Tracker names are free text, often non-ASCII; the suggestion must always
  # be a usable term.
  def test_suggested_subtype
    assert_equal 'RoadDamage', EmissionMapping.suggested_subtype(Tracker.new(name: 'road damage'))
    assert_equal 'Bug', EmissionMapping.suggested_subtype(Tracker.new(name: 'Bug'))
    assert_equal 'WorkOrder', EmissionMapping.suggested_subtype(Tracker.new(name: '障害'))
  end
end
