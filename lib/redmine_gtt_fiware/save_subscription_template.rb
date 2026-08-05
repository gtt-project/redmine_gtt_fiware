module RedmineGttFiware
  # Saves a subscription template for both create and update. The one rule
  # this class exists to hold: the project is assigned BEFORE the attributes,
  # never from them. The project comes from the route, project_id is not an
  # accepted attribute, and the project-scoping validations on the model
  # depend on the project already being set when the attributes arrive.
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

      Result.new subscription_template_saved: @subscription_template.save,
                 subscription_template: @subscription_template
    end
  end
end
