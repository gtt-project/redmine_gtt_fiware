module Issues
  Deface::Override.new(
    :virtual_path => "issues/show",
    :name => "deface_view_issues_show_format_ngsi_ld",
    :insert_after => "erb[loud]:contains('GeoJSON')",
    :original => "f936cc163030b0fa6c7b0dbdb9eb9441b1d35750",
    :partial => "issues/show/ngsi_ld"
  )
end
