module RedmineGttFiware
  # Serializes an issue as a Task of the datamodels.jp task vocabulary
  # (#152), the alternative to the frozen GTT core that an admin can choose
  # instance-wide (EmissionVocabulary). The entity id stays the IssueUrn, so
  # switching vocabularies never re-identifies an entity.
  #
  # Semantics follow RFC 8984 (JSCalendar Task) where the vocabulary does:
  # progress, a 0-9 priority, an ISO 8601 estimatedDuration. Absent data is
  # absent, as in the GTT representation.
  class TaskEntity < IssueEntity
    # The admin exposure switches are the same as in the GTT vocabulary (one
    # EmissionMapping, one set of checkboxes); each switch publishes its task
    # term here.
    TASK_TERMS = {
      'description' => 'description',
      'priority' => 'priority',
      'category' => 'category',
      'targetVersion' => 'milestone',
      'startDate' => 'start',
      'dueDate' => 'due',
      'estimatedTime' => 'estimatedDuration',
      'percentDone' => 'percentComplete',
      'parent' => 'parent',
      'assignee' => 'assignee'
    }.freeze

    # assignee is multi-valued in the task vocabulary: one Relationship
    # instance per target, told apart by datasetId (the form GeonicDB's model
    # validation accepts, see #152). Redmine has one assignee per issue.
    ASSIGNEE_DATASET_ID = 'urn:ngsi-ld:dataset:assignee:1'.freeze

    # RFC 8984 priority for an IssuePriority: its position among the active
    # priorities spread linearly over 1 (highest) to 9 (lowest), rounded.
    # 0 means undefined: a single active priority ranks nothing, and an
    # inactive priority has no place among the active ones.
    def self.priority_rank(priority)
      active = IssuePriority.active.sorted.to_a
      index = active.index(priority)
      return 0 if index.nil? || active.size < 2

      steps_from_highest = active.size - 1 - index
      1 + Rational(8 * steps_from_highest, active.size - 1).round
    end

    # Hours as an ISO 8601 duration rounded to whole minutes (1.5 -> PT1H30M);
    # durations are not normalized into days, as RFC 8984 allows.
    def self.iso8601_duration(hours)
      hours_part, minutes_part = (hours.to_f * 60).round.divmod(60)
      return 'PT0M' if hours_part.zero? && minutes_part.zero?

      duration = +'PT'
      duration << "#{hours_part}H" if hours_part.positive?
      duration << "#{minutes_part}M" if minutes_part.positive?
      duration
    end

    def to_h
      entity = {
        'id' => self.class.urn(@issue),
        'type' => 'Task',
        'name' => property(@issue.subject),
        # Redmine only knows open and closed; in-process would need a status
        # configuration this plugin does not have yet.
        'progress' => property(@issue.status.is_closed? ? 'completed' : 'needs-action'),
        'statusLabel' => property(@issue.status.name),
        'externalId' => property(@issue.id.to_s),
        'dateCreated' => datetime_property(@issue.created_on),
        'dateModified' => datetime_property(@issue.updated_on)
      }
      entity['project'] = relationship(redmine_urn('Project', @issue.project.identifier)) if @issue.project
      entity['subtype'] = property(@mapping.subtype) if @mapping&.subtype.present?
      entity['source'] = property(source_url) if source_url
      entity['location'] = geo_property if geometry?
      entity['refersTo'] = relationship(@issue.fiware_entity) if refers_to?
      entity.merge!(exposed_properties)
      entity.merge!(exposed_custom_properties)
      entity['@context'] = entity_context
      entity
    end

    private

    def exposed_properties
      return {} unless @mapping

      @mapping.exposed_standard_fields.each_with_object({}) do |field, result|
        value = send("task_#{field.underscore}")
        result[TASK_TERMS.fetch(field)] = value if value
      end
    end

    def task_description
      property(@issue.description) if @issue.description.present?
    end

    def task_priority
      property(self.class.priority_rank(@issue.priority)) if @issue.priority
    end

    # category is not a task term: GTT's extension context defines it.
    def task_category
      property(@issue.category.name) if @issue.category
    end

    # A Relationship to the version as a Milestone. The Milestone entity
    # itself is not emitted (yet); like parent, the URN is still a truthful
    # stable identifier.
    def task_target_version
      relationship(redmine_urn('Milestone', @issue.fixed_version.id)) if @issue.fixed_version
    end

    # Plain dates: Redmine has no time of day for these.
    def task_start_date
      date_property(@issue.start_date) if @issue.start_date
    end

    def task_due_date
      date_property(@issue.due_date) if @issue.due_date
    end

    def task_estimated_time
      property(self.class.iso8601_duration(@issue.estimated_hours)) if @issue.estimated_hours
    end

    def task_percent_done
      property(@issue.done_ratio.to_i)
    end

    def task_parent
      relationship(self.class.urn(@issue.parent)) if @issue.parent
    end

    # A Relationship to the assigned user or group, never a name. Publishing
    # it stays an explicit admin decision (the checkbox defaults off).
    def task_assignee
      assignee = @issue.assigned_to
      return nil unless assignee

      kind = assignee.is_a?(Group) ? 'Group' : 'Person'
      [relationship(redmine_urn(kind, assignee.id)).merge('datasetId' => ASSIGNEE_DATASET_ID)]
    end

    # urn:ngsi-ld:<Type>:redmine:<instance>:<local id>, the same shape as the
    # IssueUrn, for the things a Task points at.
    def redmine_urn(type, local_id)
      "urn:ngsi-ld:#{type}:redmine:#{Emitter.instance_id}:#{local_id}"
    end

    # The instance's task-mode context (TaskInstanceContext), under the same
    # rule as the GTT one: referenced only when a broker can reach it.
    def entity_context
      host = Setting.host_name.to_s.strip
      return CORE_CONTEXT if host.blank?

      ["#{Setting.protocol}://#{host}/fiware/task-context.jsonld", CORE_CONTEXT]
    end
  end
end
