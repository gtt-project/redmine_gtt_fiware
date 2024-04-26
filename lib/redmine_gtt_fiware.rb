module RedmineGttFiware

  def self.setup
    RedmineGttFiware::IssueStatusPatch.apply
    RedmineGttFiware::ProjectPatch.apply
    RedmineGttFiware::TrackerPatch.apply
    RedmineGttFiware::MemberPatch.apply
    ProjectsController.send :helper, RedmineGttFiware::ProjectSettingsTabs
  end

  def self.settings
    Setting.plugin_redmine_gtt_fiware
  end

end
