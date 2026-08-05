# View state for the subscription template form partials (#145). These are
# pure derivations from the template and project; extracting them keeps the
# partials markup-only and makes the branching unit-testable.
#
# All names carry the gtt_fiware_ prefix because Rails mixes every helper
# module into every view: unprefixed names like geometry_mode would be one
# core or plugin update away from a collision.
module SubscriptionTemplateFormHelper
  # A structured picker can only represent flat hashes with known keys;
  # anything richer falls back to the raw JSON textarea. `rows` is what the
  # picker renders, including the blank starter row (the add link clones the
  # last row, so with zero rows it would silently do nothing).
  PickerState = Struct.new(:pickerable, :rows) do
    alias_method :pickerable?, :pickerable
  end

  # The boundary radio needs a project polygon from redmine_gtt (#87).
  def gtt_fiware_project_boundary_available?(project)
    project.module_enabled?('gtt') && project.geom.present? &&
      project.geojson.present? &&
      project.geojson.as_json&.dig('geometry', 'type') == 'Polygon'
  end

  # Geo area radio state: anywhere (no geo fields), boundary (project
  # polygon, coveredBy) or custom georel/coords. 'boundary' only when its
  # radio is actually rendered; otherwise the stored fields show as a custom
  # query.
  def gtt_fiware_geo_mode(template, boundary_available)
    return 'anywhere' if template.expression_georel.blank?

    if boundary_available && template.expression_georel == 'coveredBy' &&
       template.expression_geometry == 'polygon'
      'boundary'
    else
      'custom'
    end
  end

  # The comma-separated form of the watched attributes JSON array; blank when
  # the stored value is not one.
  def gtt_fiware_watched_attrs_list(template)
    parsed = JSON.parse(template.attrs.to_s)
    parsed.is_a?(Array) ? parsed.join(', ') : ''
  rescue JSON::ParserError
    ''
  end

  # Entity rows are pickerable when every stored entry is a flat hash of
  # type + (idPattern | id).
  def gtt_fiware_entity_picker(template)
    entities = template.entities.is_a?(Array) ? template.entities : []
    pickerable = entities.all? do |entity|
      entity.is_a?(Hash) && entity['type'].present? &&
        (entity.keys - %w[type idPattern id]).empty? &&
        entity.keys.count { |key| %w[idPattern id].include?(key) } <= 1
    end
    rows = pickerable ? entities : []
    rows = [{ 'type' => '', 'idPattern' => '.*' }] if rows.empty? && pickerable
    PickerState.new(pickerable, rows)
  end

  # Issue geometry radio: the common case is mapping the entity's location
  # GeoProperty; custom keeps a raw GeoJSON template; none clears it. New
  # templates default to the entity's location (#102). A stored blank stays
  # None.
  def gtt_fiware_geometry_mode(template)
    if template.geometry.blank?
      template.new_record? ? 'location' : 'none'
    elsif template.geometry == '${location}'
      'location'
    else
      'custom'
    end
  end

  # Attachment rows are pickerable when every stored entry is a flat hash of
  # url/filename/description. Rows with a blank URL are skipped on
  # serialization, so the blank starter row is harmless.
  def gtt_fiware_attachment_picker(template)
    attachments = template.attachments.is_a?(Array) ? template.attachments : []
    pickerable = attachments.all? do |attachment|
      attachment.is_a?(Hash) && (attachment.keys - %w[url filename description]).empty?
    end
    rows = pickerable ? attachments : []
    rows = [{}] if rows.empty? && pickerable
    PickerState.new(pickerable, rows)
  end
end
