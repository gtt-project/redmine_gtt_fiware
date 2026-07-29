# Per-tracker custom field templates (#103, phase 2): a JSON object mapping
# issue custom field ids to template strings (${...} placeholders allowed),
# applied through safe_attributes when a notification creates an issue.
class AddIssueCustomFieldValuesToSubscriptionTemplates < ActiveRecord::Migration[6.1]
  def change
    add_column :fiware_subscription_templates, :issue_custom_field_values, :text
  end
end
