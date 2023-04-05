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

# Extends the Tracker API
namespace :projects do
  get ':project_id/trackers/:tracker_id(.:format)', to: 'tracker#index', constraints: { project_id: /[a-z0-9\-_]+/i, tracker_id: /\d+/, format: /(json|xml)/ }
end
