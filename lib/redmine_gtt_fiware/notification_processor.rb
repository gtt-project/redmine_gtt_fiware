require 'uri'
require 'rack'

module RedmineGttFiware
  # Turns one broker notification entity into a Redmine issue, applying the
  # subscription template's field mapping and the create-vs-update dedup rule.
  #
  # Since #64 the broker is used for pub/sub only: it POSTs raw NGSIv2/NGSI-LD
  # entities and the plugin does all templating here (previously the broker
  # rendered the fields via httpCustom.json). Given a template and one raw
  # entity, #process normalizes it, renders the mapped fields, decides whether
  # this is a new issue or an update to a recent one (the threshold_create
  # window, keyed on the entity id), and persists it.
  #
  # User.current must already be the template's member: the caller
  # (SubscriptionIssuesController) authenticates the webhook and sets it. The
  # issue is authored by that user and geometry/attachment work runs as them.
  class NotificationProcessor
    # Result of processing one entity. `saved` reflects Issue#save; on false the
    # issue carries validation errors for the caller to surface. `suppressed`
    # marks the federation policy skipping creation (#70): deliberate,
    # successful handling with no issue - not a failure.
    # `federated` counts local issues annotated by a federation-watch
    # notification (#70, 4c) - like suppression, deliberate successful
    # handling with no issue of its own.
    Result = Struct.new(:issue, :created, :saved, :suppressed, :federated, keyword_init: true) do
      def created?
        created
      end

      def saved?
        saved
      end

      def suppressed?
        suppressed == true
      end

      def federated?
        !federated.nil?
      end
    end

    def initialize(template, logger: Rails.logger)
      @template = template
      @logger = logger
    end

    # raw_entity: one entity hash from the notification's data[] array.
    # Echo suppression, narrowed (#70 staging finding): issues created from
    # ordinary entities (sensors, reports) ARE emitted - that is the point of
    # emission, and it cannot loop because the emitted entity's type (Issue)
    # differs from what the subscription watches. The loop only exists when
    # the notifying entity is itself an Issue (a work order creating a work
    # order creating ...), so exactly that case is suppressed - as is the
    # federation watch, which annotates local issues in place.
    def process(raw_entity)
      entity = Entity.from(raw_entity, @template.standard)
      if @template.federation_watch?
        Emitter.suppress { process_federation_update(entity) }
      elsif entity.type.to_s == 'Issue'
        Emitter.suppress { create_or_update(entity) }
      else
        create_or_update(entity)
      end
    end

    private

    def create_or_update(entity)
      existing = find_recent_issue(entity)
      existing ? process_update(existing, entity) : process_create(entity)
    end

    # A new notification for an entity already turned into an issue within the
    # threshold_create window updates that issue instead of creating a duplicate
    # (the heart of the plugin, #47). Outside the window a fresh issue is made.
    def find_recent_issue(entity)
      return nil if entity.id.blank?

      window = @template.threshold_create.to_i
      Issue
        .where(fiware_entity: entity.id, subscription_template_id: @template.id)
        .where('created_on >= ?', Time.now - window.seconds)
        .order(created_on: :desc)
        .first
    end

    def process_create(entity)
      # Federation awareness (#70, 4a): who else already works on this entity?
      siblings = federation_siblings(entity)
      if @template.federation_policy == 'suppress' && siblings.any?(&:open?)
        @logger.info "[FIWARE] Suppressed issue creation for #{entity.id}: open sibling " \
                     "work orders exist (#{siblings.select(&:open?).map(&:urn).join(', ')})"
        return Result.new(issue: nil, created: false, saved: false, suppressed: true)
      end

      issue = build_issue(entity)
      apply_new_geometry(issue, entity)
      build_attachments(issue, entity)
      result = Result.new(issue: issue, created: true, saved: issue.save)
      annotate_with_siblings(issue, siblings) if result.saved? && siblings.any?
      result
    end

    # The sibling note is a journal entry rather than part of the rendered
    # description: template output stays clean and the annotation carries its
    # own timestamp. reload first: geometry/journal callbacks touch the row
    # right after create, so a second save on the stale in-memory object
    # would raise StaleObjectError.
    def annotate_with_siblings(issue, siblings)
      lines = siblings.map do |s|
        detail = [s.subtype, s.status_label || s.status].compact.join(', ')
        link = s.source.presence || s.urn
        "* #{s.org} (#{detail}): #{link}"
      end
      issue.reload
      issue.init_journal(User.current, "#{I18n.t(:text_federation_siblings_note)}\n\n#{lines.join("\n")}")
      issue.save
    end

    # Federation push updates (#70, 4c): the notified entity is a foreign
    # organization's Issue; journal its status onto every local issue that
    # refers to the same source entity. Own emissions are ignored (the echo
    # guard the design demands), and a repeated unchanged status adds no
    # second note.
    def process_federation_update(entity)
      return Result.new(federated: 0) if own_emission?(entity)

      refers_to = entity.attributes.dig('refersTo', 'value').to_s
      return Result.new(federated: 0) if refers_to.blank?

      org = entity.id.to_s[%r{\Aurn:ngsi-ld:Issue:redmine:([^:]+):}, 1] || 'external'
      status = entity.attributes.dig('status', 'value').to_s
      status_label = entity.attributes.dig('statusLabel', 'value').to_s
      # The label wins when it only differs from the normalized status by
      # casing ("Closed" vs "closed" must not read "Closed / closed").
      status_text = [status_label.presence, status.presence].compact
                    .uniq(&:downcase).join(' / ')
      note = I18n.t(:text_federation_status_note, org: org, status: status_text, urn: entity.id)

      annotated = 0
      Issue.where(fiware_entity: refers_to, project_id: @template.project_id).find_each do |issue|
        # One note per state: skip when the latest federation note for this
        # foreign work order already says the same thing.
        last = issue.journals.where('notes LIKE ?', "%#{entity.id}%").order(id: :desc).first
        next if last && last.notes == note

        issue.init_journal(User.current, note)
        annotated += 1 if issue.save
      end
      Result.new(federated: annotated)
    end

    # The 4c echo guard: our own emitted work orders come back through a
    # watch subscription on the same tenant and must be ignored.
    def own_emission?(entity)
      instance = Emitter.instance_id
      instance.present? && entity.id.to_s.start_with?("urn:ngsi-ld:Issue:redmine:#{instance}:")
    end

    # Only when the policy asks for it, and never fatally: sibling lookup
    # failures degrade to "no siblings" inside FederationSiblings. NGSI-LD
    # only - a v2 connection has no /ngsi-ld/v1/entities to ask.
    def federation_siblings(entity)
      return [] if @template.federation_policy == 'off'
      return [] if entity.id.blank?
      return [] unless @template.broker_connection&.ngsi_ld?

      FederationSiblings.new(@template.broker_connection).for_entity(entity.id)
    end

    def process_update(issue, entity)
      journal = issue.init_journal(User.current, render(@template.notes, entity))
      apply_updated_geometry(issue, entity, journal)
      build_attachments(issue, entity)
      Result.new(issue: issue, created: false, saved: issue.save)
    end

    def build_issue(entity)
      issue = Issue.new
      issue.project = @template.project
      issue.tracker = @template.tracker
      issue.subject = render(@template.subject, entity)
      issue.description = render(@template.description, entity)
      issue.is_private = @template.is_private
      issue.status = @template.issue_status
      issue.author = User.current
      issue.category = @template.issue_category
      issue.priority = @template.issue_priority
      issue.fixed_version = @template.version
      issue.fiware_entity = entity.id
      issue.subscription_template_id = @template.id
      apply_custom_field_values(issue, entity)
      issue
    end

    # Custom field templates (#103, phase 2), rendered against the entity and
    # applied through safe_attributes so tracker availability and the acting
    # member's per-role field permissions keep holding. Blank rendered values
    # are skipped: the field is simply left unset.
    def apply_custom_field_values(issue, entity)
      templates = @template.issue_custom_field_values
      return if templates.blank?

      rendered = templates.each_with_object({}) do |(field_id, template), values|
        value = render(template, entity)
        values[field_id] = value unless value.to_s.strip.empty?
      end
      issue.safe_attributes = { 'custom_field_values' => rendered } if rendered.any?
    end

    def apply_new_geometry(issue, entity)
      return unless gtt_enabled?

      geom = rendered_geom(entity)
      issue.geom = geom if geom
    end

    def apply_updated_geometry(issue, entity, journal)
      return unless gtt_enabled?

      geom = rendered_geom(entity)
      return if geom.nil? || geom == issue.geom

      old_geom = issue.geom
      note_geofence_transition(old_geom, geom, journal)
      issue.geom = geom
      journal.details.build(property: 'attr', prop_key: 'geom', old_value: old_geom, value: geom)
    end

    # Boundary crossing notes (#87): the previous position (the issue's
    # stored geometry) and the new one are compared against the project
    # boundary; a transition is journaled. Stateless beyond the issue's
    # geometry, so a single missed notification cannot corrupt anything, and
    # a failed geometry predicate never fails the whole notification.
    def note_geofence_transition(old_geom, new_geom, journal)
      return unless @template.geofence_notes?

      fence = @template.project.geom
      return if fence.nil? || old_geom.nil? || new_geom.nil?

      was_inside = fence_contains?(fence, old_geom)
      now_inside = fence_contains?(fence, new_geom)
      return if was_inside == now_inside

      text = I18n.t(now_inside ? :text_geofence_entered : :text_geofence_left)
      journal.notes = [journal.notes.presence, text].compact.join("\n\n")
    rescue StandardError => e
      @logger.warn "[FIWARE] Geofence check failed: #{e.message}"
    end

    # Point-in-polygon against the fence; non-point geometries are reduced
    # to their centroid. Cast to the fence's factory so mixed factories
    # (fresh conversion vs. database round trip) still compare.
    def fence_contains?(fence, geom)
      geom = RGeo::Feature.cast(geom, factory: fence.factory) || geom
      point = geom.geometry_type == RGeo::Feature::Point ? geom : geom.centroid
      fence.contains?(point)
    end

    # Renders the template's geometry against the entity and converts the
    # resulting GeoJSON to a database geom. Returns nil (never raises) when
    # there is no geometry template or the GeoJSON cannot be converted, so one
    # bad geometry never fails the whole notification.
    def rendered_geom(entity)
      geometry = TemplateRenderer.render_geometry(@template.geometry, entity)
      return nil if geometry.blank?

      RedmineGtt::Conversions.to_geom(as_feature(geometry).to_json)
    rescue StandardError => e
      @logger.warn "[FIWARE] Failed to convert geometry data: #{e.message}"
      nil
    end

    # RedmineGtt::Conversions.to_geom expects a GeoJSON Feature (it calls
    # .geometry on the decoded result), so a template resolving to a bare
    # geometry — the common `${location}` case — is wrapped in one.
    def as_feature(geometry)
      return geometry unless geometry.is_a?(Hash)
      return geometry if geometry['type'].to_s == 'Feature'

      { 'type' => 'Feature', 'geometry' => geometry, 'properties' => nil }
    end

    def gtt_enabled?
      Redmine::Plugin.installed?(:redmine_gtt) && @template.project.module_enabled?('gtt')
    end

    # Fetches and attaches each rendered attachment spec. Downloads go through
    # AttachmentFetcher, which enforces the SSRF protections (https only, host
    # allowlist, public addresses only, no redirects, timeouts, content-type
    # allowlist, size limit). The stored content type is the one the server
    # responded with; a type claimed in the payload is not trusted. Rejected or
    # failed attachments are skipped and logged so one bad attachment does not
    # fail the whole notification.
    def build_attachments(issue, entity)
      specs = rendered_attachment_specs(entity)
      return if specs.empty?

      fetcher = RedmineGttFiware::AttachmentFetcher.for_template(@template)
      existing_filenames = issue.attachments.map(&:filename)

      specs.each do |spec|
        url = spec['url'].to_s
        next if url.empty?

        filename = spec['filename'].presence || File.basename(URI.parse(url).path.to_s)
        next if filename.empty? || existing_filenames.include?(filename)

        result = fetcher.fetch(url)
        uploaded_file = Rack::Multipart::UploadedFile.new(
          result.tempfile.path, result.content_type, true, filename: filename
        )
        issue.attachments.build(file: uploaded_file, description: spec['description'].to_s, author: User.current)
        existing_filenames << filename
      rescue RedmineGttFiware::AttachmentFetcher::RejectedError => e
        @logger.warn "[FIWARE] Rejected attachment download from #{url.inspect}: #{e.message}"
      rescue StandardError => e
        @logger.warn "[FIWARE] Failed to attach file: #{e.message}"
      end
    end

    # Renders the url/filename/description of each stored attachment template
    # against the entity. The stored template.attachments is an array of
    # `{ "url", "filename", "description" }` hashes whose values may contain
    # `${...}` expressions.
    def rendered_attachment_specs(entity)
      specs = @template.attachments
      return [] unless specs.is_a?(Array)

      specs.filter_map do |spec|
        next unless spec.is_a?(Hash)

        {
          'url' => render(spec['url'], entity),
          'filename' => render(spec['filename'], entity),
          'description' => render(spec['description'], entity)
        }
      end
    end

    def render(template, entity)
      TemplateRenderer.render(template, entity)
    end
  end
end
