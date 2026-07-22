# A reusable, instance-level broker configuration (#67): URL, standard, tenant
# headers and authentication live here instead of being re-entered per
# subscription template. Multiple connections per Redmine instance are a
# first-class requirement (different teams subscribe to different municipal /
# prefectural / national brokers).
#
# The auth token is stored encrypted via Redmine::Ciphering (AES-256-CBC keyed
# by configuration.yml's database_cipher_key, plaintext fallback when unset),
# the same mechanism core uses for AuthSource#account_password. `auth_mode`
# 'browser' keeps the pre-#67 behaviour for deployments that do not want the
# server to hold broker credentials: the token is supplied in the browser on
# every publish/unpublish and never stored.
class BrokerConnection < (defined?(ApplicationRecord) == 'constant' ? ApplicationRecord : ActiveRecord::Base)
  include Redmine::Ciphering

  self.table_name = 'fiware_broker_connections'

  STANDARDS = ['NGSIv2', 'NGSI-LD'].freeze
  AUTH_MODES = ['stored', 'browser'].freeze

  # Fiware-Service is a tenant name: alphanumerics and underscore, max 50
  # chars (Orion spec). Fiware-ServicePath is up to 10 `/`-separated levels of
  # the same alphabet. Invalid values fail at publish time with opaque broker
  # errors, hence validating here (#37).
  SERVICE_PATTERN = /\A[A-Za-z0-9_]{1,50}\z/
  SERVICE_PATH_PATTERN = %r{\A/[A-Za-z0-9_]{1,50}(?:/[A-Za-z0-9_]{1,50}){0,9}\z}

  has_many :subscription_templates, foreign_key: 'broker_connection_id', dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :url, presence: true
  validates :standard, inclusion: { in: STANDARDS, message: I18n.t('model.subscription_template.valid_standard') }
  validates :auth_mode, inclusion: { in: AUTH_MODES }
  validates :fiware_service, format: { with: SERVICE_PATTERN, message: I18n.t('model.broker_connection.invalid_service') }, allow_blank: true
  validates :fiware_servicepath, format: { with: SERVICE_PATH_PATTERN, message: I18n.t('model.broker_connection.invalid_service_path') }, allow_blank: true
  validate :url_must_be_http

  scope :sorted, -> { order(:name) }

  def auth_token
    read_ciphered_attribute(:auth_token)
  end

  def auth_token=(value)
    write_ciphered_attribute(:auth_token, value)
  end

  def stored_auth?
    auth_mode == 'stored'
  end

  def ngsi_ld?
    standard.to_s.casecmp('NGSI-LD').zero?
  end

  private

  def url_must_be_http
    return if url.blank?

    parsed = URI.parse(url)
    unless parsed.is_a?(URI::HTTP) && parsed.host.present?
      errors.add :url, I18n.t('model.broker_connection.invalid_url')
    end
  rescue URI::InvalidURIError
    errors.add :url, I18n.t('model.broker_connection.invalid_url')
  end
end
