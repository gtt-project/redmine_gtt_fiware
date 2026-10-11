module RedmineGttFiware
  # Serializes an issue as a Task of the datamodels.jp task vocabulary
  # (#152), typed `Issue`: the redmine subject's name for the same IRI (see
  # EmissionVocabulary). The entity id is the IssueUrn, unchanged from the
  # retired GTT Issue vocabulary, so no emitted entity was re-identified.
  #
  # Semantics follow RFC 8984 (JSCalendar Task) where the vocabulary does:
  # progress, a 0-9 priority, an ISO 8601 estimatedDuration. Absent data is
  # absent from the entity instead of null-valued.
  class IssueEntity
    CORE_CONTEXT = 'https://uri.etsi.org/ngsi-ld/v1/ngsi-ld-core-context.jsonld'.freeze

    # The admin exposure switches (EmissionMapping::STANDARD_FIELDS), each
    # with the task term it publishes.
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

    # Stable across any reconfiguration (subtype renames never change ids);
    # the federation keystone (#70).
    def self.urn(issue)
      IssueUrn.build(issue)
    end

    # mapping may be nil for pull-side rendering (#4): the representation is
    # then the always-emitted properties alone - no subtype, no exposed
    # attributes.
    def initialize(issue, mapping = nil)
      @issue = issue
      @mapping = mapping
    end

    def to_h
      entity = {
        'id' => self.class.urn(@issue),
        'type' => EmissionVocabulary::ENTITY_TYPE,
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

    # category is not a task term: the redmine subject of GTT's node defines it.
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

    # The admin-exposed custom fields (#69, step 2c), typed by field format;
    # blank values are absent from the entity like everything else.
    def exposed_custom_properties
      return {} unless @mapping

      exposed = @mapping.exposed_custom_fields
      custom_fields = IssueCustomField.where(id: exposed.keys).index_by(&:id)
      exposed.each_with_object({}) do |(cf_id, term), result|
        custom_field = custom_fields[cf_id]
        next unless custom_field

        value = custom_property(custom_field)
        result[term] = value if value
      end
    end

    def custom_property(custom_field)
      raw = @issue.custom_field_value(custom_field)
      raw = raw.reject(&:blank?) if raw.is_a?(Array)
      return nil if raw.blank? && raw != false

      case custom_field.field_format
      when 'int' then property(raw.to_i)
      when 'float' then property(raw.to_f)
      when 'bool' then property(raw == '1' || raw == true)
      when 'date'
        begin
          date_property(Date.parse(raw.to_s))
        rescue ArgumentError, TypeError
          nil
        end
      else
        property(raw.is_a?(Array) ? raw.map(&:to_s) : raw.to_s)
      end
    end

    def property(value)
      { 'type' => 'Property', 'value' => value }
    end

    def date_property(date)
      { 'type' => 'Property',
        'value' => { '@type' => 'Date', '@value' => date.iso8601 } }
    end

    def datetime_property(time)
      { 'type' => 'Property',
        'value' => { '@type' => 'DateTime', '@value' => time.utc.iso8601 } }
    end

    def relationship(object)
      { 'type' => 'Relationship', 'object' => object }
    end

    def geometry?
      @issue.respond_to?(:geom) && @issue.geom.present?
    end

    def geo_property
      { 'type' => 'GeoProperty', 'value' => strip_zero_z(RGeo::GeoJSON.encode(@issue.geom)) }
    end

    # GTT stores every geometry in a Z-enabled factory, so 2D data encodes
    # with a zero third coordinate - and some brokers (GeonicDB) validate
    # positions as strict [lon, lat] pairs. The zero-Z artifact is stripped;
    # a real altitude is kept, since RFC 7946 allows it (brokers that reject
    # 3D get a logged failure, not silently flattened data).
    def strip_zero_z(geojson)
      case geojson
      when Hash
        geojson.transform_values { |value| strip_zero_z(value) }
      when Array
        if geojson.length == 3 && geojson.all? { |c| c.is_a?(Numeric) } && geojson[2].zero?
          geojson[0, 2]
        else
          geojson.map { |value| strip_zero_z(value) }
        end
      else
        geojson
      end
    end

    # NGSI-LD Relationship objects must be URIs; issues created before the
    # notification pipeline stored entity ids, or with hand-edited values,
    # may hold something else - omit rather than fail the whole entity.
    def refers_to?
      @issue.fiware_entity.present? && @issue.fiware_entity.match?(/\A\w+:\S+\z/)
    end

    # The issue's canonical URL, from the configured host (same source as
    # email links and the callback URLs, #101). Omitted when unconfigured.
    def source_url
      host = Setting.host_name.to_s.strip
      return nil if host.blank?

      "#{Setting.protocol}://#{host}/issues/#{@issue.id}"
    end

    # urn:ngsi-ld:<Type>:redmine:<instance>:<local id>, the same shape as the
    # IssueUrn, for the things a Task points at.
    def redmine_urn(type, local_id)
      "urn:ngsi-ld:#{type}:redmine:#{Emitter.instance_id}:#{local_id}"
    end

    # Brokers dereference @context at ingestion, so the instance's published
    # context (InstanceContext) is referenced only when the instance has a
    # public identity (Setting.host_name) a broker can actually reach.
    def entity_context
      host = Setting.host_name.to_s.strip
      # Without a host, the instance context is out of reach, but the redmine
      # subject's public context still gives the task terms their meaning.
      return [EmissionVocabulary::TASK_EXTENSION_CONTEXT, CORE_CONTEXT] if host.blank?

      ["#{Setting.protocol}://#{host}/fiware/task-context.jsonld", CORE_CONTEXT]
    end
  end
end
