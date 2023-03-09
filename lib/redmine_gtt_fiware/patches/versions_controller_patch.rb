module RedmineGttFiware
  module Patches

    module VersionsControllerPatch
      def self.apply
        VersionsController.prepend self unless VersionsController < self
      end

      def show
        respond_to do |format|
          format.jsonld { render template: "ngsi_ld/version" }
          format.any { super }
        end
      end

    end
  end
end
