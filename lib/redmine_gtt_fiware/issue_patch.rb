module RedmineGttFiware
  # Issue lifecycle hooks for emission (#69, step 1). after_commit so the
  # broker only ever sees persisted state; all guards (instance id, project
  # opt-in, privacy, echo suppression) live in the Emitter.
  module IssuePatch
    def self.apply
      Issue.class_eval do
        # subscription_template_id has existed since the notification pipeline;
        # the federation panel (#70) is the first reader of the association.
        belongs_to :subscription_template, optional: true

        after_commit :emit_fiware_issue_entity, on: [:create, :update]
        after_commit :emit_fiware_issue_deletion, on: :destroy

        private

        def emit_fiware_issue_entity
          RedmineGttFiware::Emitter.upsert(self)
        end

        def emit_fiware_issue_deletion
          RedmineGttFiware::Emitter.delete(self)
        end
      end
    end
  end
end
