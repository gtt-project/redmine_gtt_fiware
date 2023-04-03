class JournalPresenter < BasePresenter
  def as_json
    json = {
      "@context": @view_context.url_for(controller: 'context', action: 'index', type: 'journals', only_path: false, format: :jsonld),
      "id": @view_context.url_for(only_path: false, format: :jsonld, normalized: @normalized),
      "type": 'Journal',
      "notes": {
        "type": 'Property',
        "value": @object.notes
      },
      "privateNotes": {
        "type": 'Property',
        "value": @object.private_notes
      },
      "createdAt": {
        "type": 'Property',
        "value": {
          "@type": 'DateTime',
          "@value": @object.created_on
        }
      },
      "hasAuthor": {
        "type": 'Relationship',
        "object": @view_context.url_for(controller: 'users', action: 'show', id: @object.user_id, only_path: false, format: :jsonld, normalized: @normalized)
      },
      "hasDetails": {
        "type": 'Property',
        "value": @object.details.map { |detail| @view_context.url_for(controller: 'details', action: 'show', id: detail.id, only_path: false, format: :jsonld, normalized: @normalized) }
      },
    }

    if @object.journalized_type == "Issue"
      json[:hasIssue] = {
        "type": 'Relationship',
        "object": @view_context.url_for(controller: 'issues', action: 'show', id: @object.journalized_id, only_path: false, format: :jsonld, normalized: @normalized)
      }
    end

    # TODO: Add custom fields if needed
    # ...

    render_ngsi(json)
  end
end
