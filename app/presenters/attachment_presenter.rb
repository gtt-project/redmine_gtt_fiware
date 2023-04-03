class AttachmentPresenter < BasePresenter
  def as_json
    json = {
      "@context": @view_context.url_for(controller: 'context', action: 'index', type: 'attachments', only_path: false, format: :jsonld),
      "id": @view_context.url_for(only_path: false, format: :jsonld, normalized: @normalized),
      "type": 'Attachment',
      "filename": {
        "type": 'Property',
        "value": @object.filename
      },
      "filesize": {
        "type": 'Property',
        "value": @object.filesize
      },
      "contentType": {
        "type": 'Property',
        "value": @object.content_type
      },
      "description": {
        "type": 'Property',
        "value": @object.description
      },
      "contentUrl": {
        "type": 'Property',
        "value": @view_context.download_named_attachment_url(@object, @object.filename)
      },
      "thumbnailUrl": {
        "type": 'Property',
        "value": @view_context.thumbnail_url(@object)
      },
      "hasAuthor": {
        "type": 'Relationship',
        "object": @view_context.url_for(controller: 'users', action: 'show', id: @object.author_id, only_path: false, format: :jsonld, normalized: @normalized)
      },
      "createdAt": {
        "type": 'Property',
        "value": @object.created_on
      },
    }

    # TODO: Add custom fields if needed
    # ...

    render_ngsi(json)
  end
end
