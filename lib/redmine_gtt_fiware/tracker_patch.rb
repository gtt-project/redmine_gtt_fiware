module RedmineGttFiware
  module TrackerPatch

    def self.apply
      Tracker.class_eval do
        has_many :subscription_templates, dependent: :delete_all
      end
    end

  end
end
