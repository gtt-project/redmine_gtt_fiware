# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

# Define a namespace for the NGSI routes
namespace :ngsi do

  # Scope the routes under the 'data-models' path
  scope 'data-models' do
    # Define a route for the context endpoint
    get '/redmine(-:type)-context', to: 'context#index', as: :context
  end

  # Define routes for issue, project, user and other resources
  %i[categories issues priorities projects statuses trackers versions users versions].each do |resource|
    resources resource, only: [:show], defaults: { format: 'json' } do
      # Add a member route with a constraint to handle JSON-LD format
      member do
        get :show, constraints: { format: 'jsonld' }
      end
    end
  end

end
