# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

# Define a namespace for the NGSI routes
namespace :ngsi do

  # Scope the routes under the 'data-models' path
  scope 'data-models' do
    # Define a route for the context endpoint
    get '/redmine(-:type)-context', to: 'context#index', as: :context
  end

  # Define routes for issue, project, user, and other resources
  %i[attachments categories details issues journals priorities projects relations statuses trackers versions users versions].each do |resource|
    resources resource, only: [:show], defaults: { format: 'json' } do
      # Add a member route with constraints to handle JSON-LD and JSON formats
      member do
        get :show, constraints: { format: /json|jsonld/ }
      end
    end
  end

  # Define routes for creating, updating, and deleting an "Issue"
  resources :issues, only: [:create, :update, :destroy], defaults: { format: 'json' } do
    member do
      # Add a member route with constraints to handle JSON-LD and JSON formats
      get :show, constraints: { format: /json|jsonld/ }
    end
  end

end

# Define route for creating issues with a notification template
scope 'fiware/subscription_template/:subscription_template_id' do
  post 'notification', to: 'subscription_issues#create'
end

# Define a route for FIWARE broker subscription templates
scope 'projects/:project_id' do
  resources :subscription_templates, only: %i(new create edit update destroy),
                            as: :project_subscription_templates do
    member do
      get :copy
      get :publish
      get :unpublish
    end
  end
end
