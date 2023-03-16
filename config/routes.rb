# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

scope 'fiware/data-models' do
  get '/redmine(-:type)-context', to: 'ngsi_ld#context', as: :context
end
