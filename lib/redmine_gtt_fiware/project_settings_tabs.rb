module RedmineGttFiware

  # hooks into the helper method that renders the project settings tabs
  module ProjectSettingsTabs

    def project_settings_tabs
      super.tap do |tabs|
        if User.current.allowed_to?(:manage_subscription_templates, @project)
          tabs << {
            name: 'subscription_templates',
            action: :manage_subscription_templates,
            partial: 'projects/settings/subscription_templates',
            label: :label_gtt_fiware_plural
          }
        end
      end
    end

  end
end

