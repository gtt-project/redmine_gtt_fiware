# Brokers behind API-key gateways (GeonicDB, Keyrock-style X-Auth-Token
# setups) do not accept Authorization: Bearer (#99). The header the token is
# sent in is a property of the broker, so it lives on the connection: blank
# keeps the previous Authorization: Bearer behaviour, any other value names
# the header the raw token is sent in (e.g. X-Api-Key).
class AddTokenHeaderToBrokerConnections < ActiveRecord::Migration[6.1]
  def change
    add_column :fiware_broker_connections, :token_header, :string
  end
end
