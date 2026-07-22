require 'uri'

# Broker configuration moves from per-template fields to reusable, instance-
# level broker connections (#67). Existing templates are data-migrated: one
# connection per distinct (url, standard, service, servicepath) combination,
# then the legacy columns are dropped.
class CreateFiwareBrokerConnections < ActiveRecord::Migration[6.1]
  def up
    create_table :fiware_broker_connections do |t|
      t.string :name, null: false
      t.string :standard, null: false, default: 'NGSI-LD'
      t.text :url, null: false
      t.string :fiware_service
      t.string :fiware_servicepath
      t.text :context
      t.string :auth_mode, null: false, default: 'stored'
      # Encrypted via Redmine::Ciphering (database_cipher_key), like
      # AuthSource#account_password in core.
      t.text :auth_token
      t.timestamps null: false
    end
    add_index :fiware_broker_connections, :name, unique: true

    add_reference :fiware_subscription_templates, :broker_connection,
                  foreign_key: { to_table: :fiware_broker_connections },
                  index: true

    migrate_template_broker_fields

    remove_column :fiware_subscription_templates, :broker_url
    remove_column :fiware_subscription_templates, :standard
    remove_column :fiware_subscription_templates, :fiware_service
    remove_column :fiware_subscription_templates, :fiware_servicepath
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # One connection per distinct broker configuration found on existing
  # templates. Tokens were never stored pre-#67, so migrated connections start
  # in 'browser' auth mode (the previous behaviour) until an admin stores one.
  def migrate_template_broker_fields
    rows = select_all(
      'SELECT id, broker_url, standard, fiware_service, fiware_servicepath ' \
      'FROM fiware_subscription_templates'
    )
    rows.to_a.group_by { |r| r.values_at('broker_url', 'standard', 'fiware_service', 'fiware_servicepath') }
        .each_with_index do |(config, templates), index|
      url, standard, service, servicepath = config
      host = begin
        URI.parse(url.to_s).host
      rescue URI::InvalidURIError
        nil
      end
      name = "#{host || url || 'broker'} (#{index + 1})"

      # connection.insert returns the inserted id through the adapter, so this
      # stays portable (no PostgreSQL-specific RETURNING clause).
      connection_id = connection.insert(<<~SQL.squish, 'create broker connection', 'id')
        INSERT INTO fiware_broker_connections
          (name, standard, url, fiware_service, fiware_servicepath, auth_mode, created_at, updated_at)
        VALUES
          (#{connection.quote(name)}, #{connection.quote(standard)}, #{connection.quote(url)}, #{connection.quote(service)},
           #{connection.quote(servicepath)}, 'browser', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL

      update(<<~SQL.squish)
        UPDATE fiware_subscription_templates
        SET broker_connection_id = #{connection.quote(connection_id)}
        WHERE id IN (#{templates.map { |t| connection.quote(t['id']) }.join(', ')})
      SQL
    end
  end
end
