module RedmineGttFiware
  module Patches

    module IssuesControllerPatch
      def self.apply
        IssuesController.prepend self unless IssuesController < self
      end

      def show
        respond_to do |format|
          format.jsonld { render template: "ngsi_ld/issue" }
          format.any { super }
        end
      end

    end
  end
end
