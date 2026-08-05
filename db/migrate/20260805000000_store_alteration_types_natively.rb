# alteration_types is a jsonb column, but the model used to JSON-encode the
# array before saving and parse it after find, so the column held a JSON
# *string* ('"[\"entityCreate\"]"') instead of a JSON array. The model now
# reads and writes the array natively; this unwraps the double-encoded
# legacy values in place. NULL rows (no types chosen) stay NULL.
class StoreAlterationTypesNatively < ActiveRecord::Migration[7.2]
  def up
    execute <<~SQL
      UPDATE fiware_subscription_templates
      SET alteration_types = (alteration_types #>> '{}')::jsonb
      WHERE jsonb_typeof(alteration_types) = 'string'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE fiware_subscription_templates
      SET alteration_types = to_jsonb(alteration_types::text)
      WHERE jsonb_typeof(alteration_types) = 'array'
    SQL
  end
end
