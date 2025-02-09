require_relative 'lib/redmine_gtt_fiware/view_hooks'

# Register MIME Types for JSON-LD format
Mime::Type.register 'application/ld+json', :jsonld

# Register the Redmine plugin
Redmine::Plugin.register :redmine_gtt_fiware do
  # Plugin metadata
  name 'Redmine GTT FIWARE plugin'
  author 'Georepublic'
  author_url 'https://github.com/georepublic'
  url 'https://github.com/gtt-project/redmine_gtt_fiware'
  description 'Adds FIWARE integration capabilities for GTT projects'
  version '2.0.1'

  # Specify the minimum required Redmine version
  requires_redmine :version_or_higher => '6.0.0'

  # Plugin settings with default values and partial view for settings
  settings(
    default: {
      'ngsi_ld_format' => false,
      'connect_via_proxy' => false,
      'fiware_broker_subscription_throttling' => '10',
    },
    partial: 'gtt_fiware/settings'
  )

  # Project module configuration with permissions
  project_module :gtt_fiware do
    permission :view_gtt_fiware_ngsi, {
      context: %i( index )
    }, read: true
    permission :manage_subscription_templates, {
      subscription_templates: %i( new edit update create destroy copy publish unpublish update_subscription_id set_subscription_id),
      projects: %i( manage_subscription_templates )
    }, require: :member
  end
end

Rails.application.config.after_initialize do
  RedmineGttFiware.setup
end

# Disable the Jbuilder generator for this plugin
Rails.application.config.generators.jb false
