require File.expand_path('../app/overrides/issues', __FILE__)

# Register MIME Types
Mime::Type.register 'application/ld+json', :jsonld

Redmine::Plugin.register :redmine_gtt_fiware do
  name 'Redmine GTT FIWARE plugin'
  author 'Georepublic'
  author_url 'https://github.com/georepublic'
  url 'https://github.com/gtt-project/redmine_gtt_fiware'
  description 'Adds FIWARE integration capabilities for GTT projects'
  version '0.1.0'

  requires_redmine :version_or_higher => '5.0.0'

  settings(
    default: {
      'ngsi_ld_format' => false
    },
    partial: 'gtt_fiware/settings'
  )

  project_module :gtt_fiware do
    permission :view_gtt_fiware_ngsi, {
      context: %i( index )
    }, read: true
  end
end

Rails.application.config.generators.jb false
