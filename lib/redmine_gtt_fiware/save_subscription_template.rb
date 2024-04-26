module RedmineGttFiware
  class SaveSubscriptionTemplate

    Result = ImmutableStruct.new :subscription_template_saved?, :subscription_template

    def self.call(*args, **kwargs)
      new(*args, **kwargs).call
    end

    def initialize(params, subscription_template: SubscriptionTemplate.new,
                           project: subscription_template.project)
      @params = params
      @subscription_template = subscription_template
      @project = project
    end


    def call
      @subscription_template.project = @project
      @subscription_template.attributes = @params

      return Result.new subscription_template_saved: @subscription_template.save,
                        subscription_template: @subscription_template
    end
  end
end
