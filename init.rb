require 'redmine'

Redmine::Plugin.register :redmine_gtt_fiware do
  name 'Redmine GTT FIWARE plugin'
  author 'Georepublic'
  author_url 'https://github.com/georepublic'
  url 'https://github.com/gtt-project/redmine_gtt_fiware'
  description 'Adds FIWARE integration capabilities for GTT projects'
  version '0.1.0'

  requires_redmine :version_or_higher => '4.2.0'

  # settings(
  #   default: {},
  #   partial: 'gtt_fiware/settings'
  # )

  # project_module :gtt_fiware do
  #   permission :view_gtt_fiware, {
  #     fiware_tags: %i( project_tags global_tags default_notes_tags )
  #   }, require: :member, read: true
  # end

end
