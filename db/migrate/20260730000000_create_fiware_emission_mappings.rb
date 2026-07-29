# Issue emission (#69, delivery step 1): an admin maps trackers to emitted
# subtypes per broker connection. One row = "issues of this tracker are
# emitted to this connection as this subtype". The exposed-attribute
# selection (design step 2) will extend this table.
class CreateFiwareEmissionMappings < ActiveRecord::Migration[6.1]
  def change
    create_table :fiware_emission_mappings do |t|
      # FK to our own table; none to core's trackers, matching core's
      # no-foreign-keys schema convention (orphans are prevented by the
      # Tracker has_many ... dependent: :delete_all patch).
      t.references :broker_connection, null: false, index: false,
                   foreign_key: { to_table: :fiware_broker_connections }
      t.references :tracker, null: false, index: false
      t.string :subtype, null: false
      t.timestamps null: false
    end
    # tracker_id leads: the hot path is the per-save lookup by tracker
    # (Emitter#each_emission); the same index enforces uniqueness.
    add_index :fiware_emission_mappings, [:tracker_id, :broker_connection_id],
              unique: true, name: 'index_fiware_emission_mappings_uniqueness'
  end
end
