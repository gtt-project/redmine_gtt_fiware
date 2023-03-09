module RedmineGttFiware
  module Patches

    module UsersControllerPatch
      def self.apply
        UsersController.prepend self unless UsersController < self
      end

      def show
        respond_to do |format|
          format.jsonld { render template: "ngsi_ld/user" }
          format.any { super }
        end
      end

    end
  end
end
