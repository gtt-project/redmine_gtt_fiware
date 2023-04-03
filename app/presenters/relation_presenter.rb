class RelationPresenter < BasePresenter
  def as_json
    json = {
      "@context": @view_context.url_for(controller: 'context', action: 'index', type: 'relations', only_path: false, format: :jsonld),
      "id": @view_context.url_for(only_path: false, format: :jsonld, normalized: @normalized),
      "type": 'Relation',
      "relationType": {
        "type": 'Property',
        "value": @object.relation_type
      },
      "fromIssue": {
        "type": 'Relationship',
        "object": @view_context.url_for(controller: 'issues', action: 'show', id: @object.issue_from_id, only_path: false, format: :jsonld, normalized: @normalized)
      },
      "toIssue": {
        "type": 'Relationship',
        "object": @view_context.url_for(controller: 'issues', action: 'show', id: @object.issue_to_id, only_path: false, format: :jsonld, normalized: @normalized)
      },
      "delay": {
        "type": 'Property',
        "value": @object.delay
      },
    }

    render_ngsi(json)
  end
end
