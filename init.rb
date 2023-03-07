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
    default: {},
    partial: 'gtt_fiware/settings'
  )

  project_module :gtt_fiware do
    permission :view_gtt_fiware, {}, require: :member, read: true
  end
end
