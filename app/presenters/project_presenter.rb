class ProjectPresenter < BasePresenter
  def as_json
    json = {
      "@context": @view_context.url_for(controller: 'context', action: 'index', type: 'projects', only_path: false, format: :jsonld),
      "id": @view_context.url_for(only_path: false, format: :jsonld, normalized: @normalized),
      "type": 'Project',
      "name": {
        "type": 'Property',
        "value": @object.name
      },
      "description": {
        "type": 'Property',
        "value": @object.description
      },
      "identifier": {
        "type": 'Property',
        "value": @object.identifier
      },
      "homepage": {
        "type": 'Property',
        "value": @object.homepage
      },
      "status": {
        "type": 'Property',
        "value": @object.status
      },
      "isPublic": {
        "type": 'Property',
        "value": @object.is_public
      },
      "createdAt": {
        "type": 'Property',
        "value": @object.created_on
      },
      "modifiedAt": {
        "type": 'Property',
        "value": @object.updated_on
      },
    }

    # Additional fields and relationships
    # ...

    render_ngsi(json)
  end
end
