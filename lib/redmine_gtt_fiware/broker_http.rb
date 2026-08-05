require 'net/http'
require 'uri'

module RedmineGttFiware
  # The one place broker HTTP requests are built and sent. Every caller
  # (publish/unpublish, sync, preview, emission, federation queries) goes
  # through here, so timeouts and the auth/tenant header conventions cannot
  # drift between call sites.
  #
  # Responses are returned as-is and network errors are raised as-is: what a
  # failure means (log and continue, show the user an error, degrade to an
  # empty list) is the caller's decision, not the transport's.
  class BrokerHttp
    # Short timeouts: broker calls run inside web requests or issue saves,
    # where a hung broker must not pin a worker for net/http's 60s defaults.
    OPEN_TIMEOUT = 5 # seconds
    READ_TIMEOUT = 10 # seconds

    REQUEST_CLASSES = {
      get: Net::HTTP::Get,
      post: Net::HTTP::Post,
      patch: Net::HTTP::Patch,
      delete: Net::HTTP::Delete
    }.freeze

    # Sends one request to a full URL (usually built from
    # BrokerConnection#api_base) and returns the Net::HTTPResponse.
    #
    # connection: supplies the tenant headers and the auth header scheme.
    # token: the auth token to send, turned into the connection's header via
    #   BrokerConnection#token_header_pair; nil or blank sends no auth header.
    #   Passed separately from the connection because browser/proxied modes
    #   supply a per-request token that is never stored on the connection.
    # body: a String is sent verbatim, anything else is JSON-encoded.
    def self.request(method, url, connection:, token: nil, headers: {}, body: nil, content_type: nil)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request_headers = connection ? connection.tenant_headers.dup : {}
      if connection && (pair = connection.token_header_pair(token))
        request_headers[pair.first] = pair.last
      end
      request_headers['Content-Type'] = content_type if content_type
      request_headers.merge!(headers)

      # request_uri (not path) keeps any query string and never yields the
      # empty path Net::HTTP rejects for a bare-host URL.
      request = REQUEST_CLASSES.fetch(method).new(uri.request_uri, request_headers)
      request.body = body.is_a?(String) ? body : body.to_json if body
      http.request(request)
    end
  end
end
