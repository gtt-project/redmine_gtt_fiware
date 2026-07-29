# Issue emission (#69, delivery step 1): an admin maps trackers to emitted
# subtypes per broker connection. One row = "issues of this tracker are
# emitted to this connection as this subtype". The exposed-attribute
# selection (design step 2) will extend this table.
class CreateFiwareEmissionMappings < ActiveRecord::Migration[6.1]
  def change
    create_table :fiware_emission_mappings do |t|
      t.references :broker_connection, null: false, index: false
      t.references :tracker, null: false, index: false
      t.string :subtype, null: false
      t.timestamps null: false
    end
    add_index :fiware_emission_mappings, [:broker_connection_id, :tracker_id],
              unique: true, name: 'index_fiware_emission_mappings_uniqueness'
  end
end
