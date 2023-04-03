class CategoryPresenter < BasePresenter
  def as_json
    json = {
      "@context": @view_context.url_for(controller: 'context', action: 'index', type: 'categories', only_path: false, format: :jsonld),
      "id": @view_context.url_for(only_path: false, format: :jsonld, normalized: @normalized),
      "type": 'Category',
      "name": {
        "type": 'Property',
        "value": @object.name
      },
    }

    json[:hasProject] = {
      "type": 'Relationship',
      "object": @view_context.url_for(controller: 'projects', action: 'show', id: @object.project_id, only_path: false, format: :jsonld, normalized: @normalized)
    } if @object.project

    json[:hasAssignee] = {
      "type": 'Relationship',
      "object": @view_context.url_for(controller: 'users', action: 'show', id: @object.assigned_to_id, only_path: false, format: :jsonld, normalized: @normalized)
    } if @object.assigned_to

    # TODO: Add custom fields if needed
    # ...

    render_ngsi(json)
  end
end
