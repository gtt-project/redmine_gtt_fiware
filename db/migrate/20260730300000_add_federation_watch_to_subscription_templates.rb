# Federation push updates (#70, 4c): a watch template subscribes to the
# emitted Issue type itself and journals foreign status changes onto
# correlated local issues instead of creating issues.
class AddFederationWatchToSubscriptionTemplates < ActiveRecord::Migration[6.1]
  def change
    add_column :fiware_subscription_templates, :federation_watch, :boolean,
               null: false, default: false
  end
end
