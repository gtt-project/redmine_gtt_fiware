class StatusPresenter < BasePresenter
  def as_json
    json = {
      "@context": @view_context.url_for(controller: 'context', action: 'index', type: 'statuses', only_path: false, format: :jsonld),
      "id": @view_context.url_for(only_path: false, format: :jsonld, normalized: @normalized),
      "type": 'Status',
      "name": {
        "type": 'Property',
        "value": @object.name
      },
      "isClosed": {
        "type": 'Property',
        "value": @object.is_closed
      },
    }

    render_ngsi(json)
  end
end
