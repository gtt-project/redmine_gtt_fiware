module RedmineGttFiware
  def self.setup_controller_patches
    RedmineGttFiware::Patches::IssuesControllerPatch.apply
    RedmineGttFiware::Patches::ProjectsControllerPatch.apply
    RedmineGttFiware::Patches::UsersControllerPatch.apply
  end
end
