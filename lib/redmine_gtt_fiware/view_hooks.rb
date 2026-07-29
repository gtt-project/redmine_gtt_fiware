module RedmineGttFiware
  class ViewHooks < Redmine::Hook::ViewListener
    render_on :view_layouts_base_html_head, inline: <<-END
      <%= stylesheet_link_tag 'gtt_fiware', plugin: 'redmine_gtt_fiware' %>
      <%= javascript_include_tag 'gtt_fiware', plugin: 'redmine_gtt_fiware' %>
    END

    # Federation panel (#70, 4b) below the issue description.
    render_on :view_issues_show_description_bottom, partial: 'gtt_fiware/federation_panel'

    # The link to the issue's NGSI-LD representation (#4) is not a hook: it
    # belongs in the core "Also available in" list, which has no hook, so it
    # is a Deface override (app/overrides/issues/show.rb).
  end
end
