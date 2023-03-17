# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

# Define a namespace for the NGSI routes
namespace :ngsi do

  # Scope the routes under the 'data-models' path
  scope 'data-models' do
    # Define a route for the context endpoint
    get '/redmine(-:type)-context', to: 'context#index', as: :context
  end

  # Define routes for the issue resources
  resources :issues, only: [:show], defaults: { format: 'json' } do
    # Add a member route with a constraint to handle JSON-LD format
    member do
      get :show, constraints: { format: 'jsonld' }
    end
  end

  # Define routes for the project resources
  resources :projects, only: [:show], defaults: { format: 'json' } do
    # Add a member route with a constraint to handle JSON-LD format
    member do
      get :show, constraints: { format: 'jsonld' }
    end
  end

  # Define routes for the user resources
  resources :users, only: [:show], defaults: { format: 'json' } do
    # Add a member route with a constraint to handle JSON-LD format
    member do
      get :show, constraints: { format: 'jsonld' }
    end
  end

end
