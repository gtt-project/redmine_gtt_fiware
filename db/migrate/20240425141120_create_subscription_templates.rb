class CreateSubscriptionTemplates < ActiveRecord::Migration[5.2]
  def change
    create_table :fiware_subscription_templates do |t|
      t.string :standard, null: false
      t.text :broker_url, null: false
      t.text :fiware_service
      t.text :fiware_servicepath
      t.text :name, null: false
      t.datetime :expires
      t.string :status, null: false
      t.text :context

      t.text :subscription_id
      t.jsonb :entities
      t.jsonb :attrs
      t.text :expression_query
      t.text :expression_georel
      t.string :expression_geometry
      t.text :expression_coords
      t.jsonb :alteration_types
      t.boolean :notify_on_metadata_change, default: true

      t.string :subject, null: false
      t.text :description
      t.jsonb :attachments
      t.boolean :is_private, default: false

      t.references :project, index: true, foreign_key: true, null: false
      t.references :tracker, index: true, foreign_key: true, null: false
      t.references :version, index: true, foreign_key: true
      t.references :issue_status, index: true, foreign_key: true, null: false
      t.references :issue_category, index: true, foreign_key: true
      t.references :issue_priority, index: true, foreign_key: { to_table: :enumerations }
      t.references :member, index: true, foreign_key: true, null: false

      t.text :comment
      t.timestamps null: false
    end
  end
end
