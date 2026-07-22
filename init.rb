require_relative 'lib/redmine_gtt_fiware/view_hooks'

# Register the Redmine plugin
Redmine::Plugin.register :redmine_gtt_fiware do
  # Plugin metadata
  name 'Redmine GTT FIWARE plugin'
  author 'Daniel Kastl'
  author_url 'https://github.com/dkastl'
  url 'https://github.com/gtt-project/redmine_gtt_fiware'
  description 'Adds FIWARE integration capabilities for GTT projects'
  version '2.0.1'

  # Specify the minimum required Redmine version
  requires_redmine :version_or_higher => '6.0.0'

  # Plugin settings with default values and partial view for settings
  settings(
    default: {
      'connect_via_proxy' => false,
      'fiware_broker_subscription_throttling' => '10',
      'attachment_download_hosts' => '',
      'attachment_download_content_types' => "image/jpeg\nimage/png\nimage/gif\nimage/webp\napplication/pdf\ntext/plain\ntext/csv\napplication/json",
    },
    partial: 'gtt_fiware/settings'
  )

  # Project module configuration with permissions
  project_module :gtt_fiware do
    permission :manage_subscription_templates, {
      subscription_templates: %i( new edit update create destroy copy publish unpublish update_subscription_id set_subscription_id),
      projects: %i( manage_subscription_templates )
    }, require: :member
  end
end

Rails.application.config.after_initialize do
  RedmineGttFiware.setup
end
