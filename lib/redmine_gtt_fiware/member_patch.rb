module RedmineGttFiware
  module MemberPatch

    def self.apply
      Member.class_eval do
        has_many :subscription_templates, dependent: :nullify
      end
    end

  end
end
