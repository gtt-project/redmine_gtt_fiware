# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

scope 'fiware/ngsi/ld' do
  get 'context', to: 'ngsi_ld#context', as: :context
end

scope 'fiware/data-models' do
  get '/:tracker_id/context', to: 'ngsi_ld#data_model', as: :data_model
end
