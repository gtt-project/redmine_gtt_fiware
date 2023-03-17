# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

namespace :ngsi do
  scope 'fiware/data-models' do
    get '/redmine(-:type)-context', to: 'ngsi_ld#context', as: :context
  end

  resources :issues, only: [:show], defaults: { format: 'json' } do
    member do
      get :show, constraints: { format: 'jsonld' }
    end
  end

  resources :projects, only: [:show], defaults: { format: 'json' } do
    member do
      get :show, constraints: { format: 'jsonld' }
    end
  end

  resources :users, only: [:show], defaults: { format: 'json' } do
    member do
      get :show, constraints: { format: 'jsonld' }
    end
  end

end
