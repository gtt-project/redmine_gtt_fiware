module RedmineGttFiware
  module IssueStatusPatch

    def self.apply
      IssueStatus.class_eval do
        has_many :subscription_templates, dependent: :delete_all
      end
    end

  end
end
