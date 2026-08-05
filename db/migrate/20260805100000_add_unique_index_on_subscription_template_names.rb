# The per-project name uniqueness was validation-only; a unique index makes
# it hold under concurrency too. Existing duplicates would fail the index
# creation, so they are disambiguated first (oldest keeps its name).
class AddUniqueIndexOnSubscriptionTemplateNames < ActiveRecord::Migration[7.2]
  def up
    say_with_time 'disambiguating duplicate subscription template names' do
      execute <<~SQL
        UPDATE fiware_subscription_templates t
        SET name = t.name || ' (' || t.id || ')'
        WHERE EXISTS (
          SELECT 1 FROM fiware_subscription_templates other
          WHERE other.project_id = t.project_id
            AND other.name = t.name
            AND other.id < t.id
        )
      SQL
    end
    add_index :fiware_subscription_templates, [:project_id, :name],
              unique: true, name: 'index_fiware_subscription_templates_on_project_and_name'
  end

  def down
    remove_index :fiware_subscription_templates,
                 name: 'index_fiware_subscription_templates_on_project_and_name'
  end
end
