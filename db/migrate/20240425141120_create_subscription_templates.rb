class CreateSubscriptionTemplates < ActiveRecord::Migration[5.2]
  def change
    create_table :subscription_templates do |t|
      t.string :name
      t.string :subject
      t.string :broker_url
      t.text :description
      t.jsonb :entities
      t.jsonb :condition
      t.boolean :is_private, default: false
      t.references :project, index: true, foreign_key: true, type: :integer
      t.references :tracker, index: true, foreign_key: true, type: :integer
      t.references :issue_status, index: true, foreign_key: true, type: :integer
      t.references :member, index: true, foreign_key: true, type: :integer
      t.datetime :expires
      t.boolean :status, default: true

      t.timestamps null: false
    end
  end
end
