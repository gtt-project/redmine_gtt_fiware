# Boundary crossing notes (#87): when enabled, the plugin compares the
# entity's previous position (the issue's stored geometry) and the new one
# against the project boundary on each notification, and journals
# enter/leave transitions.
class AddGeofenceNotesToSubscriptionTemplates < ActiveRecord::Migration[6.1]
  def change
    add_column :fiware_subscription_templates, :geofence_notes, :boolean, default: false, null: false
  end
end
