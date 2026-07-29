# Admin-exposable attributes per emission mapping (#69, step 2b): which of
# the issue's standard fields are published as entity properties. Stored as
# JSON ({"standard": [...]}) so step 2c can add custom fields without another
# migration. Default: nothing beyond the frozen core is exposed.
class AddExposedAttributesToEmissionMappings < ActiveRecord::Migration[6.1]
  def change
    add_column :fiware_emission_mappings, :exposed_attributes, :text
  end
end
