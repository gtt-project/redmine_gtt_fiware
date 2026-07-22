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
    # issue carries validation errors for the caller to surface.
    Result = Struct.new(:issue, :created, :saved, keyword_init: true) do
      def created?
        created
      end

      def saved?
        saved
      end
    end

    def initialize(template, logger: Rails.logger)
      @template = template
      @logger = logger
    end

    # raw_entity: one entity hash from the notification's data[] array.
    def process(raw_entity)
      entity = Entity.from(raw_entity, @template.standard)
      existing = find_recent_issue(entity)
      existing ? process_update(existing, entity) : process_create(entity)
    end

    private

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
      issue = build_issue(entity)
      apply_new_geometry(issue, entity)
      build_attachments(issue, entity)
      Result.new(issue: issue, created: true, saved: issue.save)
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
      issue
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
      issue.geom = geom
      journal.details.build(property: 'attr', prop_key: 'geom', old_value: old_geom, value: geom)
    end

    # Renders the template's geometry against the entity and converts the
    # resulting GeoJSON to a database geom. Returns nil (never raises) when
    # there is no geometry template or the GeoJSON cannot be converted, so one
    # bad geometry never fails the whole notification.
    def rendered_geom(entity)
      geometry = TemplateRenderer.render_geometry(@template.geometry, entity)
      return nil if geometry.blank?

      RedmineGtt::Conversions.to_geom(geometry.to_json)
    rescue StandardError => e
      @logger.warn "[FIWARE] Failed to convert geometry data: #{e.message}"
      nil
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
