# Seeds one broker connection and one subscription template per auth mode
# (stored / relayed / browser), all pointing at the fake_broker.py echo broker,
# for the manual auth-mode drill in doc/release_verification.md.
#
# Idempotent: reruns update the same records (matched by name).
#
# Usage, from the Redmine root:
#
#   VERIFY_PROJECT=<identifier> bundle exec rails runner \
#     plugins/redmine_gtt_fiware/doc/scripts/seed_verification.rb
#
# Environment:
#   VERIFY_PROJECT              project identifier (required; the GTT FIWARE
#                               module must be enabled and the project must
#                               have at least one member and tracker)
#   FAKE_BROKER_SERVER_URL      broker URL as reachable FROM THE REDMINE SERVER
#                               (default http://fakebroker:9999 -- container
#                               network alias; hostnames must not contain
#                               underscores, brokers reject them in URLs)
#   FAKE_BROKER_BROWSER_URL     broker URL as reachable FROM THE BROWSER
#                               (default http://localhost:9999)
#   VERIFY_MEMBER_LOGIN         login of the member to author issues as
#                               (default: the project's first member)

project = Project.find_by!(identifier: ENV.fetch('VERIFY_PROJECT'))
server_url = ENV.fetch('FAKE_BROKER_SERVER_URL', 'http://fakebroker:9999')
browser_url = ENV.fetch('FAKE_BROKER_BROWSER_URL', 'http://localhost:9999')

member =
  if ENV['VERIFY_MEMBER_LOGIN'].present?
    project.members.joins(:user).find_by!(users: { login: ENV['VERIFY_MEMBER_LOGIN'] })
  else
    project.members.joins(:user).first or raise 'project has no members'
  end
tracker = project.trackers.first or raise 'project has no trackers'

connections = {
  'stored' => { name: 'Verification broker (stored)', url: server_url,
                auth_token: 'stored-secret-789' },
  # 'proxied' is the internal name for the UI's "relayed" mode.
  'proxied' => { name: 'Verification broker (relayed)', url: server_url },
  # A custom token header on the browser connection also exercises the
  # connection-configurable token header (#99) in the browser-mode JS.
  'browser' => { name: 'Verification broker (browser)', url: browser_url,
                 token_header: 'X-Api-Key' }
}

connections.each do |auth_mode, attrs|
  connection = BrokerConnection.find_or_initialize_by(name: attrs[:name])
  connection.assign_attributes(
    standard: 'NGSIv2',
    auth_mode: auth_mode,
    url: attrs[:url],
    token_header: attrs[:token_header],
    auth_token: attrs[:auth_token]
  )
  connection.save!

  template = SubscriptionTemplate.find_or_initialize_by(
    name: "Verification: #{auth_mode} mode", project_id: project.id
  )
  template.assign_attributes(
    broker_connection: connection,
    status: 'active',
    tracker_id: tracker.id,
    member_id: member.id,
    issue_status_id: IssueStatus.sorted.first.id,
    issue_priority_id: IssuePriority.default&.id || IssuePriority.first.id,
    subject: '${type} ${id} (verification)',
    description: 'Auth mode drill against the fake broker; safe to delete.',
    entities_string: '[{"type": "VerificationEntity", "idPattern": ".*"}]',
    geometry_string: 'null'
  )
  template.save!
  puts "#{template.name}: template ##{template.id} -> #{connection.name} (#{connection.url})"
end

puts "Done. Drill: open the project's FIWARE settings tab, type a token into"
puts 'the token box, publish/unpublish each template, and compare the broker'
puts 'log against the expected-results table in doc/release_verification.md.'
