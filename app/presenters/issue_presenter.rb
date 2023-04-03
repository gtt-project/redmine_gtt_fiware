class IssuePresenter < BasePresenter
  def as_json
    json = {
      "@context": @view_context.url_for(controller: 'context', action: 'index', type: 'issues', only_path: false, format: :jsonld),
      "id": @view_context.url_for(only_path: false, format: :jsonld, normalized: @normalized),
      "type": 'Issue',
      "subject": {
        "type": 'Property',
        "value": @object.subject
      },
      "closedDate": {
        "type": 'Property',
        "value": nil
      },
      "isPrivate": {
        "type": 'Property',
        "value": @object.is_private
      },
      "createdAt": {
        "type": 'Property',
        "value": {
          "@type": 'DateTime',
          "@value": @object.created_on
        }
      },
      "modifiedAt": {
        "type": 'Property',
        "value": {
          "@type": 'DateTime',
          "@value": @object.updated_on
        }
      },
    }

    if @object.closed_on
      json[:closedDate] = {
        "type": 'Property',
        "value": {
          "@type": 'DateTime',
          "@value": @object.closed_on
        }
      }
    end

    if @object.project
      json[:hasProject] = {
        "type": 'Relationship',
        "object": @view_context.url_for(controller: 'projects', action: 'show', id: @object.project_id, only_path: false, format: :jsonld, normalized: @normalized)
      }
    end

    if @object.tracker
      json[:hasTracker] = {
        "type": 'Relationship',
        "object": @view_context.url_for(controller: 'trackers', action: 'show', id: @object.tracker_id, only_path: false, format: :jsonld, normalized: @normalized)
      }
    end

    if @object.status
      json[:hasStatus] = {
        "type": 'Relationship',
        "object": @view_context.url_for(controller: 'statuses', action: 'show', id: @object.status_id, only_path: false, format: :jsonld, normalized: @normalized)
      }
    end

    if @object.priority
      json[:hasPriority] = {
        "type": 'Relationship',
        "object": @view_context.url_for(controller: 'priorities', action: 'show', id: @object.priority_id, only_path: false, format: :jsonld, normalized: @normalized)
      }
    end

    if @object.author
      json[:hasAuthor] = {
        "type": 'Relationship',
        "object": @view_context.url_for(controller: 'users', action: 'show', id: @object.author_id, only_path: false, format: :jsonld, normalized: @normalized)
      }
    end

    unless @object.disabled_core_fields.include?('parent_issue_id') || @object.parent_id.nil?
      json[:hasParent] = {
        "type": 'Relationship',
        "object": @view_context.url_for(controller: 'issues', action: 'show', id: @object.parent_id, only_path: false, format: :jsonld, normalized: @normalized)
      }
    end

    unless @object.disabled_core_fields.include?('start_date')
      json[:startDate] = {
        "type": 'Property',
        "value": {
          "@type": 'DateTime',
          "@value": @object.start_date
        }
      }
    end

    unless @object.disabled_core_fields.include?('due_date')
      json[:dueDate] = {
        "type": 'Property',
        "value": {
          "@type": 'DateTime',
          "@value": @object.due_date
        }
      }
    end

    unless @object.disabled_core_fields.include?('estimated_hours')
      json[:estimatedHours] = {
        "type": 'Property',
        "value": @object.estimated_hours
      }
      json[:totalEstimatedHours] = {
        "type": 'Property',
        "value": @object.total_estimated_hours
      }
    end

    unless @object.disabled_core_fields.include?('done_ratio')
      json[:doneRatio] = {
        "type": 'Property',
        "value": @object.done_ratio
      }
    end

    unless @object.disabled_core_fields.include?('description')
      json[:description] = {
        "type": 'Property',
        "value": @object.description
      }
    end

    unless @object.disabled_core_fields.include?('assigned_to_id') || @object.assigned_to_id.nil?
      json[:hasAssignee] = {
        "type": 'Relationship',
        "object": @view_context.url_for(controller: 'users', action: 'show', id: @object.assigned_to_id, only_path: false, format: :jsonld, normalized: @normalized)
      }
    end

    unless @object.disabled_core_fields.include?('category_id') || (@object.category.nil? && @object.project.issue_categories.none?) || @object.category.nil?
      json[:hasCategory] = {
        "type": 'Relationship',
        "object": @view_context.url_for(controller: 'categories', action: 'show', id: @object.category_id, only_path: false, format: :jsonld, normalized: @normalized)
      }
    end

    unless @object.disabled_core_fields.include?('fixed_version_id') || (@object.fixed_version.nil? && @object.assignable_versions.none?) || @object.fixed_version.nil?
      json[:hasVersion] = {
        "type": 'Relationship',
        "object": @view_context.url_for(controller: 'versions', action: 'show', id: @object.fixed_version_id, only_path: false, format: :jsonld, normalized: @normalized)
      }
    end

    if User.current.allowed_to?(:view_time_entries, @project)
      json[:spentHours] = {
        "type": 'Property',
        "value": @object.spent_hours
      }
      json[:totalSpentHours] = {
        "type": 'Property',
        "value": @object.total_spent_hours
      }
    end

    if @object.geom
      json[:location] = {
        "type": 'GeoProperty',
        "value": @object.geojson['geometry']
      }
    else
      json[:location] = nil
    end

    json[:allowedStatuses] = {
      "type": 'Relationship',
      "object": @object.new_statuses_allowed_to(User.current).map { |status| @view_context.url_for(controller: 'statuses', action: 'show', id: status.id, only_path: false, format: :jsonld, normalized: @normalized) }
    }

    json[:hasAttachments] = {
      "type": 'Relationship',
      "object": @object.attachments.map { |attachment| @view_context.url_for(controller: 'attachments', action: 'show', id: attachment.id, only_path: false, format: :jsonld, normalized: @normalized) }
    }

    json[:hasChildren] = {
      "type": 'Relationship',
      "object": @object.children.map { |child| @view_context.url_for(controller: 'issues', action: 'show', id: child.id, only_path: false, format: :jsonld, normalized: @normalized) }
    }

    json[:hasRelations] = {
      "type": 'Relationship',
      "object": @object.relations.map { |relation| @view_context.url_for(controller: 'relations', action: 'show', id: relation.id, only_path: false, format: :jsonld, normalized: @normalized) }
    }

    json[:hasJournals] = {
      "type": 'Relationship',
      "object": @object.journals.map { |journal| @view_context.url_for(controller: 'journals', action: 'show', id: journal.id, only_path: false, format: :jsonld, normalized: @normalized) }
    }

    json[:hasWatchers] = {
      "type": 'Relationship',
      "object": @object.watcher_users.map { |user| @view_context.url_for(controller: 'users', action: 'show', id: user.id, only_path: false, format: :jsonld, normalized: @normalized) }
    }

    # Handle custom fields
    CustomFieldHelper.process_custom_fields(json, @object.visible_custom_field_values, @view_context, @normalized)

    render_ngsi(json)
  end
end
