class VersionPresenter < BasePresenter
  def as_json
    json = {
      "@context": @view_context.url_for(controller: 'context', action: 'index', type: 'versions', only_path: false, format: :jsonld),
      "id": @view_context.url_for(only_path: false, format: :jsonld, normalized: @normalized),
      "type": 'Version',
      "name": {
        "type": 'Property',
        "value": @object.name
      },
      "description": {
        "type": 'Property',
        "value": @object.description
      },
      "status": {
        "type": 'Property',
        "value": @object.status
      },
      "dueDate": {
        "type": 'Property',
        "value": @object.effective_date
      },
      "sharing": {
        "type": 'Property',
        "value": @object.sharing
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

    if User.current.allowed_to?(:view_time_entries, @object.project)
      json[:estimatedHours] = {
        "type": 'Property',
        "value": @object.visible_fixed_issues.estimated_hours
      }
      json[:spentHours] = {
        "type": 'Property',
        "value": @object.spent_hours
      }
    end

    # Handle custom fields
    CustomFieldHelper.process_custom_fields(json, @object.visible_custom_field_values, @view_context, @normalized)

    render_ngsi(json)
  end
end
