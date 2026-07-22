# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

# Define route for creating issues with a notification template
scope 'fiware/subscription_template/:subscription_template_id' do
  post 'notification', to: 'subscription_issues#create'
  # Registration is a state-changing callback (it stores the broker-assigned
  # subscription id), so it is POST, not GET. It is a JSON API endpoint
  # (format: 'json'): it is authenticated by API key via accept_api_auth, and
  # Redmine exempts api_request? requests from the CSRF token check in its own
  # verify_authenticity_token, so no forgery-protection skip is needed here.
  post 'registration/:subscription_id', to: 'subscription_templates#set_subscription_id',
       defaults: { format: 'json' }
end

# Instance-level broker connections, managed by admins (#67).
resources :broker_connections, except: [:show]

# Define a route for FIWARE broker subscription templates
scope 'projects/:project_id' do
  resources :subscription_templates, only: %i(new create edit update destroy),
                            as: :project_subscription_templates do
    member do
      # copy is read-only (it prefills a curl command), so it stays GET.
      get :copy
      # publish/unpublish change state (they call the broker and update the
      # stored subscription id), so they are POST, not GET.
      post :publish
      post :unpublish
      # sync reconciles local state with the broker (#13): it may clear the
      # stored subscription id or update the status, so it is POST too.
      post :sync
      patch :update_subscription_id
    end
  end
end
