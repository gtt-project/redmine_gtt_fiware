require File.expand_path('../../test_helper', __FILE__)

# The NGSI-LD entry in the issue page's "Also available in" list (#4).
# An integration test on purpose: what is under test is a Deface override and
# its CSS selector, and those only take effect when the real issues/show
# template renders. A stale selector would silently insert nothing.
class IssueOtherFormatsTest < Redmine::IntegrationTest
  fixtures :all

  INSTANCE_SETTINGS = { 'fiware_instance_id' => 'test-town' }.freeze

  def setup
    log_user('jsmith', 'jsmith')
    @issue = Issue.find(1)
  end

  def test_lists_ngsi_ld_among_the_other_formats
    with_settings plugin_redmine_gtt_fiware: INSTANCE_SETTINGS do
      get "/issues/#{@issue.id}"
    end
    assert_response :success
    assert_select 'p.other-formats' do
      assert_select "a[href=?]", "/fiware/issues/#{@issue.id}/entity", text: 'NGSI-LD'
    end
  end

  def test_omits_ngsi_ld_without_an_instance_identifier
    with_settings plugin_redmine_gtt_fiware: { 'fiware_instance_id' => '' } do
      get "/issues/#{@issue.id}"
    end
    assert_response :success
    assert_select 'p.other-formats'
    assert_select 'p.other-formats a', text: 'NGSI-LD', count: 0
  end
end
