# Adds NGSI-LD to Redmine's own "Also available in" list at the bottom of the
# issue page, next to PDF, Atom and (with redmine_gtt) GeoJSON, instead of
# repeating a second export line of its own below the description.
#
# Anchored on the Atom link so the entry lands last, after the GeoJSON one
# redmine_gtt inserts after the PDF link.
Deface::Override.new(
  virtual_path: 'issues/show',
  name: 'deface_view_issues_show_format_ngsi_ld',
  insert_after: "erb[loud]:contains('Atom')",
  partial: 'issues/show/ngsi_ld'
)
