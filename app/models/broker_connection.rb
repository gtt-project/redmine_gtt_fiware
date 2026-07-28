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

  # How this broker is reached, and where its token comes from (#95):
  #
  #   stored  - token stored encrypted here, broker called from the server
  #   proxied - token entered in the browser per request, server relays the call
  #   browser - token entered in the browser, browser calls the broker directly
  #
  # Whether the browser can reach a broker at all (private network, firewall,
  # CORS) is a property of that broker, which is why this lives here and not
  # in the plugin settings.
  AUTH_MODES = ['stored', 'proxied', 'browser'].freeze

  # Used when neither the template nor the connection sets one.
  DEFAULT_THROTTLING = 10

  # New connections start at the default so the form shows the value that will
  # actually apply. Records loaded from the database keep their stored value,
  # including nil, for which SubscriptionTemplate#effective_throttling still
  # falls back to DEFAULT_THROTTLING.
  attribute :throttling, :integer, default: DEFAULT_THROTTLING

  # Fiware-Service is a tenant name: alphanumerics and underscore, max 50
  # chars (Orion spec). Fiware-ServicePath is up to 10 `/`-separated levels of
  # the same alphabet. Invalid values fail at publish time with opaque broker
  # errors, hence validating here (#37).
  SERVICE_PATTERN = /\A[A-Za-z0-9_]{1,50}\z/
  SERVICE_PATH_PATTERN = %r{\A/[A-Za-z0-9_]{1,50}(?:/[A-Za-z0-9_]{1,50}){0,9}\z}

  # RFC 7230 header field-name (token) characters only, so a configured
  # token_header can never inject additional headers (#99).
  HEADER_NAME_PATTERN = /\A[!#$%&'*+\-.^_`|~0-9A-Za-z]+\z/

  has_many :subscription_templates, foreign_key: 'broker_connection_id', dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :url, presence: true
  validates :standard, inclusion: { in: STANDARDS, message: I18n.t('model.subscription_template.valid_standard') }
  validates :auth_mode, inclusion: { in: AUTH_MODES }
  validates :throttling, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :fiware_service, format: { with: SERVICE_PATTERN, message: I18n.t('model.broker_connection.invalid_service') }, allow_blank: true
  validates :fiware_servicepath, format: { with: SERVICE_PATH_PATTERN, message: I18n.t('model.broker_connection.invalid_service_path') }, allow_blank: true
  # Typing "Authorization" must mean the same as leaving the field blank
  # (Authorization: Bearer), not a raw token in the Authorization header --
  # otherwise the two spellings of the default silently differ.
  before_validation :normalize_token_header
  validates :token_header, format: { with: HEADER_NAME_PATTERN, message: I18n.t('model.broker_connection.invalid_token_header') }, allow_blank: true
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

  # The broker call runs on the server for both stored and proxied; only
  # 'browser' talks to the broker straight from the browser.
  def server_side?
    ['stored', 'proxied'].include?(auth_mode)
  end

  # Modes that need the user to supply a token in the browser (the token box
  # on the subscription template list).
  def browser_token?
    ['proxied', 'browser'].include?(auth_mode)
  end

  def ngsi_ld?
    standard.to_s.casecmp('NGSI-LD').zero?
  end

  # How the broker expects its token (#99). Blank token_header keeps the
  # Authorization: Bearer scheme; any other value names the header the raw
  # token is sent in (X-Api-Key, X-Auth-Token, ...).
  def token_header_name
    token_header.presence || 'Authorization'
  end

  # 'Bearer ' when the token goes into Authorization, '' otherwise. Exposed
  # separately from token_header_pair because the browser-mode views prepend
  # it to a token that only exists client-side.
  def token_value_prefix
    token_header.present? ? '' : 'Bearer '
  end

  # [header_name, header_value] for the given token, or nil when it is blank.
  # Every broker call (stored, proxied, preview, sync) builds its auth header
  # through this so the scheme cannot drift between call sites.
  def token_header_pair(token)
    return nil if token.blank?

    [token_header_name, "#{token_value_prefix}#{token}"]
  end

  private

  def normalize_token_header
    self.token_header = token_header.to_s.strip.presence
    self.token_header = nil if token_header&.casecmp('authorization')&.zero?
  end

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
