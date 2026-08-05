# Shared body of the subscription REST API responses (#22).
#
# What is deliberately NOT rendered: the per-subscription webhook secret (it
# authenticates broker notifications, so it must never leave the server) and
# anything from the connection beyond its identity (the stored broker token
# lives there).
module SubscriptionTemplatesHelper
  def render_api_subscription_template(template, api)
    api.id template.id
    api.name template.name
    api.status template.status
    api.subscription_id template.subscription_id
    api.published !template.subscription_id.blank?

    render_api_reference(api, :project, template.project, :name)
    render_api_reference(api, :broker_connection, template.broker_connection, :name,
                         standard: template.broker_connection&.standard)

    # What to watch.
    api.entities template.entities.presence || []
    api.attrs api_json_array(template.attrs)
    api.expression_query template.expression_query
    api.expression_georel template.expression_georel
    api.expression_geometry template.expression_geometry
    api.expression_coords template.expression_coords
    api.alteration_types template.alteration_types || []
    api.notify_on_metadata_change template.notify_on_metadata_change
    api.throttling template.throttling
    api.expires template.expires

    # What to create.
    render_api_reference(api, :tracker, template.tracker, :name)
    render_api_reference(api, :issue_status, template.issue_status, :name)
    render_api_reference(api, :issue_priority, template.issue_priority, :name)
    render_api_reference(api, :issue_category, template.issue_category, :name)
    render_api_reference(api, :version, template.version, :name)
    render_api_reference(api, :member, template.member, :name)
    api.subject template.subject
    api.description template.description
    api.notes template.notes
    api.geometry template.geometry
    api.attachments template.attachments.presence || []
    api.issue_custom_field_values template.issue_custom_field_values
    api.threshold_create template.threshold_create
    api.is_private template.is_private

    # Federation and boundary behaviour.
    api.federation_policy template.federation_policy
    api.federation_watch template.federation_watch
    api.geofence_notes template.geofence_notes

    api.context template.context
    api.comment template.comment
    api.created_at template.created_at
    api.updated_at template.updated_at
  end

  # An association rendered as an id/name reference, like core does for
  # project/tracker/status. Skipped entirely when the association is empty.
  #
  # __send__, not send: the API builders are BasicObjects, so `send` is not
  # defined on them and would be swallowed by method_missing as a tag named
  # "send" - silently dropping the reference. Attributes only, no block: the
  # builders ignore attributes when a block is given.
  def render_api_reference(api, key, record, name_method, extra = {})
    return if record.nil?

    api.__send__(key, { id: record.id, name: record.public_send(name_method) }.merge(extra.compact))
  end

  # attrs is stored as a JSON string (the watched attribute names); the API
  # presents it as what it means, an array of strings.
  def api_json_array(value)
    return [] if value.blank?
    return value if value.is_a?(Array)

    parsed = JSON.parse(value)
    parsed.is_a?(Array) ? parsed : []
  rescue JSON::ParserError
    []
  end
end
