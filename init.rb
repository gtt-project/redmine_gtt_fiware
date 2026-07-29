require_relative 'lib/redmine_gtt_fiware/view_hooks'

# Register the Redmine plugin
Redmine::Plugin.register :redmine_gtt_fiware do
  # Plugin metadata
  name 'Redmine GTT FIWARE plugin'
  author 'Daniel Kastl'
  author_url 'https://github.com/dkastl'
  url 'https://github.com/gtt-project/redmine_gtt_fiware'
  description 'Adds FIWARE integration capabilities for GTT projects'
  version '3.2.0'

  # Specify the minimum required Redmine version
  requires_redmine :version_or_higher => '6.0.0'

  # Plugin settings with default values and partial view for settings
  settings(
    default: {
      'attachment_download_hosts' => '',
      'attachment_download_content_types' => "image/jpeg\nimage/png\nimage/gif\nimage/webp\napplication/pdf\ntext/plain\ntext/csv\napplication/json",
      # Issue emission (#69) stays off until an instance id is set; it is
      # baked into every emitted URN and must stay stable once chosen.
      'fiware_instance_id' => '',
    },
    partial: 'gtt_fiware/settings'
  )

  # Broker connections are instance-level and admin-managed. The :icon (with
  # :plugin, so it resolves from this plugin's own sprite rather than core's)
  # and the matching :html class are both required for the admin menu item to
  # render its sprite icon, exactly as core's own admin_menu items do.
  menu :admin_menu, :fiware_broker_connections,
       { controller: 'broker_connections', action: 'index' },
       caption: :label_broker_connection_plural,
       icon: 'cloud-data-connection',
       plugin: :redmine_gtt_fiware,
       html: { class: 'icon icon-cloud-data-connection' }

  # Project module configuration with permissions
  project_module :gtt_fiware do
    permission :manage_subscription_templates, {
      subscription_templates: %i( index show new edit update create destroy copy preview allowed_statuses publish unpublish sync update_subscription_id set_subscription_id),
      projects: %i( manage_subscription_templates )
    }, require: :member
  end

  # Issue emission is an explicit per-project opt-in (#69): sharing issue data
  # with a broker must never be a side effect of enabling subscriptions, so it
  # is a separate module. The permission is a pure flag (public, no actions)
  # because a module only appears in project settings through a permission.
  project_module :gtt_fiware_emission do
    permission :gtt_fiware_emission, {}, public: true
  end
end

# Deface overrides are not autoloaded (they define no constants), so they are
# required here and hidden from Zeitwerk, the same way redmine_gtt does it.
Dir.glob("#{Rails.root}/plugins/redmine_gtt_fiware/app/overrides/**/*.rb").each do |path|
  Rails.autoloaders.main.ignore(path)
  require path
end

Rails.application.config.after_initialize do
  RedmineGttFiware.setup
end
