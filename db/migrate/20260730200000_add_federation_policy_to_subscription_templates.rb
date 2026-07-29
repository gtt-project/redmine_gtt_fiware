# Federation awareness at creation time (#70, 4a): what to do when another
# organization already has an Issue entity for the same source entity.
# 'off' keeps today's behaviour; 'annotate' creates the issue and notes the
# siblings; 'suppress' skips creation while a foreign open Issue exists.
class AddFederationPolicyToSubscriptionTemplates < ActiveRecord::Migration[6.1]
  def change
    add_column :fiware_subscription_templates, :federation_policy, :string,
               null: false, default: 'off'
  end
end
