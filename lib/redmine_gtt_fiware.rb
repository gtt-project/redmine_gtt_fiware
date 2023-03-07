module RedmineGttFiware
  def self.setup_controller_patches
    RedmineGttFiware::Patches::IssuesControllerPatch.apply
  end
end

