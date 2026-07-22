class AddWebhookSecretToSubscriptionTemplates < ActiveRecord::Migration[6.1]
  def change
    add_column :fiware_subscription_templates, :webhook_secret, :string
  end
end
