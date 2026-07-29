require File.expand_path('../../test_helper', __FILE__)

class FederationControllerTest < ActionController::TestCase
  fixtures :projects, :trackers, :projects_trackers, :issue_statuses,
           :users, :email_addresses, :members, :member_roles, :roles,
           :enumerations, :issues

  def setup
    @request.session[:user_id] = 1
    @connection = BrokerConnection.create!(
      name: 'Panel broker', standard: 'NGSI-LD',
      url: 'https://broker.example.com', auth_mode: 'stored',
      context: 'https://uri.etsi.org/ngsi-ld/v1/ngsi-ld-core-context.jsonld'
    )
    @template = SubscriptionTemplate.create!(
      broker_connection_id: @connection.id, status: 'active',
      name: 'Panel template', subject: 'S ${id}', description: 'D',
      entities_string: '[{"idPattern": ".*", "type": "WasteContainer"}]',
      project_id: 1, tracker_id: 1, issue_status_id: 1,
      issue_priority_id: IssuePriority.first.id, member_id: 1
    )
    @issue = Issue.find(1)
    @issue.update_columns(fiware_entity: 'urn:ngsi-ld:WasteContainer:042',
                          subscription_template_id: @template.id)
  end

  def sibling
    RedmineGttFiware::FederationSiblings::Sibling.new(
      urn: 'urn:ngsi-ld:Issue:redmine:nexco-east:7', org: 'nexco-east',
      subtype: 'WorkOrder', status: 'open', status_label: 'In Progress',
      title: 'Container full', source: 'https://other.example/issues/7'
    )
  end

  def test_renders_siblings
    RedmineGttFiware::FederationSiblings.any_instance.stubs(:for_entity).returns([sibling])
    get :show, params: { id: @issue.id }
    assert_response :success
    assert_select 'div.gtt-fiware-federation-panel'
    assert_select 'li strong', text: 'nexco-east'
    assert_select 'a[href=?]', 'https://other.example/issues/7'
  end

  def test_no_content_without_siblings
    RedmineGttFiware::FederationSiblings.any_instance.stubs(:for_entity).returns([])
    get :show, params: { id: @issue.id }
    assert_response :no_content
  end

  def test_no_content_without_a_fiware_entity
    @issue.update_columns(fiware_entity: nil)
    get :show, params: { id: @issue.id }
    assert_response :no_content
  end

  # The panel shows broker data correlated to the issue, so seeing the issue
  # is the requirement.
  def test_invisible_issue_is_404
    @request.session[:user_id] = nil
    with_settings login_required: '1' do
      get :show, params: { id: @issue.id }
      assert_response 302 # redirected to login by check_if_login_required
    end
  end
end
