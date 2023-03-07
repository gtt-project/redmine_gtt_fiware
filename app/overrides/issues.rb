module Issues
  Deface::Override.new(
    :virtual_path => "issues/show",
    :name => "deface_view_issues_show_format_ngsi_ld",
    :insert_after => "erb[loud]:contains('PDF')",
    :original => "1419e0dcba37f62ff95372d41d9b73845889d826",
    :partial => "issues/show/ngsi_ld"
  )
end
