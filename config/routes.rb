# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

namespace :ngsi do
  scope 'data-models' do
    get '/redmine(-:type)-context', to: 'context#index', as: :context
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
