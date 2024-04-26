module RedmineGttFiware
  module ProjectPatch

    def self.apply
      Project.class_eval do
        has_many :subscription_templates, dependent: :delete_all
      end
    end

  end
end

