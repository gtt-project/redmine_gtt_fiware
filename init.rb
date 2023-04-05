# Require the issues overrides file
# require File.expand_path('../app/overrides/issues', __FILE__)

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
  version '0.1.0'

  # Specify the minimum required Redmine version
  requires_redmine :version_or_higher => '5.0.0'

  # Plugin settings with default values and partial view for settings
  settings(
    default: {
      'ngsi_ld_format' => false
    },
    partial: 'gtt_fiware/settings'
  )

  # Project module configuration with permissions
  project_module :gtt_fiware do
    permission :view_gtt_fiware_ngsi, {
      context: %i( index )
    }, read: true

    permission :view_tracker_field_definitions, {
      field_definitions: [:index]
    }, read: true
  end
end

# Disable the Jbuilder generator for this plugin
Rails.application.config.generators.jb false
