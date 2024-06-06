module RedmineGttFiware
  class ViewHooks < Redmine::Hook::ViewListener
    render_on :view_layouts_base_html_head, inline: <<-END
      <%= stylesheet_link_tag 'gtt_fiware', plugin: 'redmine_gtt_fiware' %>
      <%= javascript_include_tag 'gtt_fiware', plugin: 'redmine_gtt_fiware' %>
    END
  end
end
