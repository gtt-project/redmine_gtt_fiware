# "Connect via proxy" and subscription throttling were global plugin settings
# from before connections existed (#95). Both are now per connection:
#
#   auth_mode  stored | proxied | browser   (was stored | browser, plus a
#              global proxy flag, which made "stored + not proxied" an
#              impossible state that silently behaved as proxied)
#   throttling connection default, overridable per subscription template
#
# The current global values are carried onto existing rows so behaviour does
# not change on upgrade.
class MoveTransportAndThrottlingToConnections < ActiveRecord::Migration[6.1]
  DEFAULT_THROTTLING = 10

  def up
    add_column :fiware_broker_connections, :throttling, :integer
    add_column :fiware_subscription_templates, :throttling, :integer

    settings = Setting.plugin_redmine_gtt_fiware || {}

    throttling = settings['fiware_broker_subscription_throttling'].presence&.to_i || DEFAULT_THROTTLING
    execute "UPDATE fiware_broker_connections SET throttling = #{connection.quote(throttling)}"

    # A browser-mode connection was relayed through the server whenever the
    # global proxy flag was on; that is exactly the new 'proxied' mode.
    if to_bool(settings['connect_via_proxy'])
      execute "UPDATE fiware_broker_connections SET auth_mode = 'proxied' WHERE auth_mode = 'browser'"
    end
  end

  def down
    remove_column :fiware_broker_connections, :throttling
    remove_column :fiware_subscription_templates, :throttling
    execute "UPDATE fiware_broker_connections SET auth_mode = 'browser' WHERE auth_mode = 'proxied'"
  end

  private

  # Redmine stores checkbox settings as '1' / '0' strings.
  def to_bool(value)
    ['1', 'true', true].include?(value)
  end
end
