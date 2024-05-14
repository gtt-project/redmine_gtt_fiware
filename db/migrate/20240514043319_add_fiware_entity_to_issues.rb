class AddFiwareEntityToIssues < ActiveRecord::Migration[5.2]
  def change
    add_column :issues, :fiware_entity, :string
    add_reference :issues, :subscription_template, index: true
  end
end
