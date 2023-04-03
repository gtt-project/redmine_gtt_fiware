class DetailPresenter < BasePresenter
  def as_json
    json = {
      "@context": @view_context.url_for(controller: 'context', action: 'index', type: 'details', only_path: false, format: :jsonld),
      "id": @view_context.url_for(only_path: false, format: :jsonld, normalized: @normalized),
      "type": 'Detail',
      "property": {
        "type": 'Property',
        "value": @object.property
      },
      "propKey": {
        "type": 'Property',
        "value": @object.prop_key
      },
      "oldValue": {
        "type": 'Property',
        "value": @object.old_value
      },
      "value": {
        "type": 'Property',
        "value": @object.value
      },
      "hasJournal": {
        "type": 'Relationship',
        "object": @view_context.url_for(controller: 'journals', action: 'show', id: @object.journal_id, only_path: false, format: :jsonld, normalized: @normalized)
      },
    }

    # TODO: Add custom fields if needed
    # ...

    render_ngsi(json)
  end
end
