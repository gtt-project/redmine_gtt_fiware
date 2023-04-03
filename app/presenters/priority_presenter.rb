class PriorityPresenter < BasePresenter
  def as_json
    json = {
      "@context": @view_context.url_for(controller: 'context', action: 'index', type: 'priorities', only_path: false, format: :jsonld),
      "id": @view_context.url_for(only_path: false, format: :jsonld, normalized: @normalized),
      "type": 'Priority',
      "name": {
        "type": 'Property',
        "value": @object.name
      },
      "isDefault": {
        "type": 'Property',
        "value": @object.is_default
      },
      "active": {
        "type": 'Property',
        "value": @object.active
      },
    }

    # TODO: Add custom fields if needed
    # ...

    render_ngsi(json)
  end
end
