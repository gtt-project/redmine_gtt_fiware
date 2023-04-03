class TrackerPresenter < BasePresenter
  def as_json
    json = {
      "@context": @view_context.url_for(controller: 'context', action: 'index', type: 'trackers', only_path: false, format: :jsonld),
      "id": @view_context.url_for(only_path: false, format: :jsonld, normalized: @normalized),
      "type": 'Tracker',
      "name": {
        "type": 'Property',
        "value": @object.name
      },
      "description": {
        "type": 'Property',
        "value": @object.description
      },
      "standardFields": {
        "type": 'Property',
        "value": @object.core_fields
      },
    }

    if @object.default_status
      json[:defaultStatus] = {
        "type": 'Relationship',
        "object": @view_context.url_for(controller: 'statuses', action: 'show', id: @object.default_status.id, only_path: false, format: :jsonld, normalized: @normalized)
      }
    end

    # TODO: add custom fields

    render_ngsi(json)
  end
end
