# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

# Define route for creating issues with a notification template
scope 'fiware/subscription_template/:subscription_template_id' do
  # format: 'json' is what makes Redmine treat this as an api_request? and
  # therefore exempt it from the CSRF token check, instead of the endpoint
  # skipping verify_authenticity_token itself (#61 established this pattern).
  post 'notification', to: 'subscription_issues#create', defaults: { format: 'json' }
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

# The instance's self-published JSON-LD context (#69, step 2): core terms
# plus the configured emission subtypes. Public - brokers dereference it at
# ingestion and consumers read the schema from it.
get 'fiware/context.jsonld', to: 'fiware_contexts#show', format: false

# Issue-page federation panel (#70, 4b): other organizations' work orders
# for the same source entity, fetched asynchronously.
get 'fiware/issues/:id/federation', to: 'federation#show'

# A single issue as an NGSI-LD entity (#4): the emitter's representation,
# available on demand (session or API key).
get 'fiware/issues/:id/entity', to: 'fiware_entities#show', defaults: { format: 'json' }

# Define a route for FIWARE broker subscription templates
scope 'projects/:project_id' do
  # index and show exist for the REST API (#22); in a browser they redirect to
  # the project's FIWARE tab and to the edit form respectively, which are the
  # HTML surfaces for the same data.
  resources :subscription_templates, only: %i(index show new create edit update destroy),
                            as: :project_subscription_templates do
    collection do
      # Live preview (#68): renders the issue templates against a sample
      # entity fetched from the broker. Works for unsaved templates, hence a
      # collection route. POST (it carries form state), CSRF-protected (the
      # form JS sends the token header).
      post :preview
      # Workflow-allowed issue statuses for a tracker/member pair (#103):
      # read-only lookup the form calls when either select changes.
      get :allowed_statuses
    end
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
