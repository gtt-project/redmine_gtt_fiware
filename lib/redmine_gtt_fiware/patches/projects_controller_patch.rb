module RedmineGttFiware
  module Patches

    module ProjectsControllerPatch
      def self.apply
        ProjectsController.prepend self unless ProjectsController < self
      end

      def show
        respond_to do |format|
          format.jsonld { render template: "ngsi_ld/project" }
          format.any { super }
        end
      end

    end
  end
end
