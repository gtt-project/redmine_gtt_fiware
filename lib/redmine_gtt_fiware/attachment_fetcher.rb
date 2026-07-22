require 'net/http'
require 'resolv'
require 'ipaddr'
require 'tempfile'

module RedmineGttFiware
  # Downloads notification attachments with SSRF protections:
  #
  # - https URLs only
  # - the host must be allowlisted (the subscription template's broker
  #   host plus any hosts configured in the plugin settings)
  # - every address the host resolves to must be public, and the TCP
  #   connection is pinned to the vetted address so a DNS rebind between
  #   check and request cannot redirect the fetch
  # - redirects are not followed
  # - connect/read timeouts apply
  # - the response content type must be allowlisted
  # - the body is streamed and the download aborted once it exceeds the
  #   size limit (Redmine's attachment size limit)
  class AttachmentFetcher
    class RejectedError < StandardError; end

    Result = Struct.new(:tempfile, :content_type, keyword_init: true)

    OPEN_TIMEOUT = 5   # seconds
    READ_TIMEOUT = 10  # seconds

    # Used when Redmine's attachment_max_size is 0 (unlimited uploads):
    # remote downloads still need a hard cap.
    FALLBACK_MAX_BYTES = 25.megabytes

    DEFAULT_CONTENT_TYPES = %w[
      image/jpeg
      image/png
      image/gif
      image/webp
      application/pdf
      text/plain
      text/csv
      application/json
    ].freeze

    # Address ranges that must never be fetched from, beyond what
    # IPAddr#private?/#loopback?/#link_local? already cover.
    BLOCKED_RANGES = %w[
      0.0.0.0/8
      100.64.0.0/10
      192.0.0.0/24
      198.18.0.0/15
      224.0.0.0/3
      ::/128
      64:ff9b::/96
    ].map { |cidr| IPAddr.new(cidr) }.freeze

    def self.for_template(template)
      settings = Setting.plugin_redmine_gtt_fiware
      hosts = settings['attachment_download_hosts'].to_s.split(/[\s,]+/)
      begin
        broker_host = URI.parse(template.broker_url.to_s).host
        hosts << broker_host if broker_host
      rescue URI::InvalidURIError
        # An unparsable broker URL simply contributes no host.
      end

      content_types = settings['attachment_download_content_types'].to_s.split(/[\s,]+/)
      content_types = DEFAULT_CONTENT_TYPES if content_types.empty?

      max_size_kb = Setting.attachment_max_size.to_i
      max_bytes = max_size_kb > 0 ? max_size_kb.kilobytes : FALLBACK_MAX_BYTES

      new(allowed_hosts: hosts, allowed_content_types: content_types, max_bytes: max_bytes)
    end

    # resolver and transport are injectable for tests. transport is a
    # callable receiving (uri, ip, &block) that yields a Net::HTTPResponse
    # (or an object quacking like one) to the block.
    def initialize(allowed_hosts:, allowed_content_types:, max_bytes:, resolver: Resolv, transport: nil)
      @allowed_hosts = allowed_hosts.map { |h| h.to_s.strip.downcase }.reject(&:empty?)
      @allowed_content_types = allowed_content_types.map { |t| t.to_s.strip.downcase }.reject(&:empty?)
      @max_bytes = max_bytes
      @resolver = resolver
      @transport = transport || method(:start_request)
    end

    # Returns a Result on success, raises RejectedError otherwise.
    def fetch(url)
      uri = parse_https_uri(url)
      check_host!(uri)
      ip = vetted_address(uri.host)
      @transport.call(uri, ip) do |response|
        process_response(response)
      end
    end

    private

    def parse_https_uri(url)
      uri = URI.parse(url.to_s)
      raise RejectedError, 'only https attachment URLs are allowed' unless uri.is_a?(URI::HTTPS)
      raise RejectedError, 'attachment URL has no host' if uri.host.to_s.empty?
      uri
    rescue URI::InvalidURIError
      raise RejectedError, 'attachment URL is not a valid URI'
    end

    def check_host!(uri)
      host = uri.host.downcase
      return if @allowed_hosts.include?(host)
      raise RejectedError, "host #{host} is not on the attachment download allowlist"
    end

    def vetted_address(host)
      addresses = @resolver.getaddresses(host)
      raise RejectedError, "could not resolve #{host}" if addresses.empty?
      ips = addresses.map { |address| IPAddr.new(address.to_s) }
      if ips.any? { |ip| blocked_address?(ip) }
        raise RejectedError, "#{host} resolves to a non-public address"
      end
      ips.first.to_s
    end

    def blocked_address?(ip)
      # Unwrap IPv4-mapped IPv6 addresses so they are judged by the IPv4
      # rules. Ranges are compared per family: IPAddr#include? would
      # otherwise map every IPv4 address into IPv6 space and match it
      # against IPv6 ranges.
      ip = ip.native if ip.ipv6? && ip.ipv4_mapped?
      return true if ip.private? || ip.loopback? || ip.link_local?
      BLOCKED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) }
    end

    def start_request(uri, ip)
      http = Net::HTTP.new(uri.host, uri.port)
      http.ipaddr = ip
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http.start do |session|
        session.request_get(uri.request_uri) do |response|
          return yield(response)
        end
      end
    rescue Timeout::Error, SystemCallError, SocketError, IOError,
           OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError => e
      raise RejectedError, "download failed: #{e.class}: #{e.message}"
    end

    def process_response(response)
      code = response.code.to_i
      unless (200..299).cover?(code)
        raise RejectedError, "unexpected HTTP response #{response.code} (redirects are not followed)"
      end
      check_content_type!(response.content_type)
      check_declared_length!(response['Content-Length'])
      tempfile = read_body_limited(response)
      Result.new(tempfile: tempfile, content_type: media_type_of(response.content_type))
    end

    def check_content_type!(content_type)
      media_type = media_type_of(content_type)
      allowed = @allowed_content_types.any? do |pattern|
        if pattern.end_with?('/*')
          media_type.start_with?(pattern[0..-2])
        else
          media_type == pattern
        end
      end
      return if allowed
      raise RejectedError, "content type #{media_type.empty? ? '(none)' : media_type} is not allowed"
    end

    def media_type_of(content_type)
      content_type.to_s.split(';').first.to_s.strip.downcase
    end

    def check_declared_length!(content_length)
      return if content_length.to_s.empty?
      return if content_length.to_i <= @max_bytes
      raise RejectedError, "attachment exceeds the maximum size of #{@max_bytes} bytes"
    end

    def read_body_limited(response)
      tempfile = Tempfile.new(['gtt_fiware_attachment', '.bin'])
      tempfile.binmode
      bytes = 0
      response.read_body do |chunk|
        bytes += chunk.bytesize
        if bytes > @max_bytes
          raise RejectedError, "attachment exceeds the maximum size of #{@max_bytes} bytes"
        end
        tempfile.write(chunk)
      end
      tempfile.rewind
      tempfile
    rescue StandardError
      if tempfile
        tempfile.close
        tempfile.unlink
      end
      raise
    end
  end
end
