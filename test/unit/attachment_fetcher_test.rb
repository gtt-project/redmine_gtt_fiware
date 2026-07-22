require File.expand_path('../../test_helper', __FILE__)

class AttachmentFetcherTest < ActiveSupport::TestCase

  # Resolves hosts from a static map; unknown hosts resolve to nothing.
  class FakeResolver
    def initialize(map)
      @map = map
    end

    def getaddresses(host)
      @map.fetch(host, [])
    end
  end

  # Quacks like the parts of Net::HTTPResponse the fetcher uses.
  class FakeResponse
    attr_reader :code

    def initialize(code: '200', content_type: 'image/png', body_chunks: ['data'], content_length: nil)
      @code = code
      @content_type = content_type
      @body_chunks = body_chunks
      @content_length = content_length
    end

    def content_type
      @content_type
    end

    def [](name)
      @content_length if name.to_s.casecmp('content-length').zero?
    end

    def read_body(&block)
      @body_chunks.each(&block)
    end
  end

  NO_TRANSPORT = lambda do |_uri, _ip, &_block|
    raise 'transport must not be reached'
  end

  def build_fetcher(overrides = {})
    RedmineGttFiware::AttachmentFetcher.new(**{
      allowed_hosts: ['broker.example.com'],
      allowed_content_types: ['image/png', 'application/pdf'],
      max_bytes: 1024,
      resolver: FakeResolver.new('broker.example.com' => ['203.0.113.10']),
      transport: NO_TRANSPORT,
    }.merge(overrides))
  end

  def with_response(response)
    lambda { |_uri, _ip, &block| block.call(response) }
  end

  def assert_rejected(fetcher, url, message_fragment)
    error = assert_raises(RedmineGttFiware::AttachmentFetcher::RejectedError) do
      fetcher.fetch(url)
    end
    assert_match message_fragment, error.message
  end

  def test_rejects_http_urls
    assert_rejected build_fetcher, 'http://broker.example.com/file.png', /https/
  end

  def test_rejects_non_http_schemes
    assert_rejected build_fetcher, 'ftp://broker.example.com/file.png', /https/
    assert_rejected build_fetcher, 'file:///etc/passwd', /https/
  end

  def test_rejects_invalid_urls
    assert_rejected build_fetcher, 'https://exa mple.com/x', /valid URI/
  end

  def test_rejects_hosts_not_on_the_allowlist
    assert_rejected build_fetcher, 'https://evil.example.org/file.png', /allowlist/
  end

  def test_host_match_is_case_insensitive
    resolver = FakeResolver.new('BROKER.example.com'.downcase => ['203.0.113.10'])
    fetcher = build_fetcher(
      resolver: resolver,
      transport: with_response(FakeResponse.new)
    )
    result = fetcher.fetch('https://BROKER.example.com/file.png')
    assert_equal 'image/png', result.content_type
  ensure
    result&.tempfile&.close!
  end

  def test_rejects_unresolvable_hosts
    fetcher = build_fetcher(resolver: FakeResolver.new({}))
    assert_rejected fetcher, 'https://broker.example.com/file.png', /could not resolve/
  end

  def test_rejects_hosts_resolving_to_non_public_addresses
    %w[
      10.0.0.1
      172.16.0.1
      192.168.1.1
      127.0.0.1
      169.254.169.254
      100.64.0.1
      0.0.0.0
      198.18.0.1
      224.0.0.1
      ::1
      fe80::1
      fc00::1
      ff02::1
      2001:2::1
      ::ffff:10.0.0.1
    ].each do |address|
      fetcher = build_fetcher(resolver: FakeResolver.new('broker.example.com' => [address]))
      assert_rejected fetcher, 'https://broker.example.com/file.png', /non-public address/
    end
  end

  def test_rejects_when_any_resolved_address_is_non_public
    resolver = FakeResolver.new('broker.example.com' => ['203.0.113.10', '10.0.0.1'])
    fetcher = build_fetcher(resolver: resolver)
    assert_rejected fetcher, 'https://broker.example.com/file.png', /non-public address/
  end

  def test_rejects_redirects
    fetcher = build_fetcher(transport: with_response(FakeResponse.new(code: '302')))
    assert_rejected fetcher, 'https://broker.example.com/file.png', /302 \(redirects are not followed\)/
  end

  def test_rejects_non_redirect_errors_without_redirect_wording
    fetcher = build_fetcher(transport: with_response(FakeResponse.new(code: '500')))
    error = assert_raises(RedmineGttFiware::AttachmentFetcher::RejectedError) do
      fetcher.fetch('https://broker.example.com/file.png')
    end
    assert_match(/unexpected HTTP response 500/, error.message)
    assert_no_match(/redirects/, error.message)
  end

  def test_rejects_disallowed_content_types
    fetcher = build_fetcher(transport: with_response(FakeResponse.new(content_type: 'text/html')))
    assert_rejected fetcher, 'https://broker.example.com/file.png', /content type text\/html/
  end

  def test_content_type_wildcards_match_subtypes
    fetcher = build_fetcher(
      allowed_content_types: ['image/*'],
      transport: with_response(FakeResponse.new(content_type: 'image/webp'))
    )
    result = fetcher.fetch('https://broker.example.com/file.webp')
    assert_equal 'image/webp', result.content_type
  ensure
    result&.tempfile&.close!
  end

  def test_rejects_oversized_content_length
    response = FakeResponse.new(content_length: '2048')
    fetcher = build_fetcher(transport: with_response(response))
    assert_rejected fetcher, 'https://broker.example.com/file.png', /maximum size/
  end

  def test_rejects_oversized_streamed_bodies_without_content_length
    response = FakeResponse.new(body_chunks: ['a' * 600, 'b' * 600])
    fetcher = build_fetcher(transport: with_response(response))
    assert_rejected fetcher, 'https://broker.example.com/file.png', /maximum size/
  end

  def test_fetches_allowed_attachments
    response = FakeResponse.new(
      content_type: 'application/pdf; charset=binary',
      body_chunks: ['%PDF', '-1.7']
    )
    fetcher = build_fetcher(transport: with_response(response))
    result = fetcher.fetch('https://broker.example.com/report.pdf')
    assert_equal 'application/pdf', result.content_type
    assert_equal '%PDF-1.7', result.tempfile.read
  ensure
    result&.tempfile&.close!
  end

  def test_for_template_allows_the_broker_host_and_configured_hosts
    template = SubscriptionTemplate.new(broker_connection: BrokerConnection.new(url: 'https://broker.example.com:1026/v2'))
    with_settings_hosts("cdn.example.net\nMedia.Example.org") do
      fetcher = RedmineGttFiware::AttachmentFetcher.for_template(template)
      hosts = fetcher.instance_variable_get(:@allowed_hosts)
      assert_equal %w[cdn.example.net media.example.org broker.example.com], hosts
    end
  end

  def test_for_template_falls_back_to_default_content_types
    template = SubscriptionTemplate.new(broker_connection: BrokerConnection.new(url: 'https://broker.example.com'))
    with_settings_hosts('') do
      fetcher = RedmineGttFiware::AttachmentFetcher.for_template(template)
      types = fetcher.instance_variable_get(:@allowed_content_types)
      assert_equal RedmineGttFiware::AttachmentFetcher::DEFAULT_CONTENT_TYPES, types
      assert_not_includes types, 'text/html'
    end
  end

  private

  def with_settings_hosts(hosts)
    saved = Setting.plugin_redmine_gtt_fiware
    Setting.plugin_redmine_gtt_fiware = saved.merge(
      'attachment_download_hosts' => hosts,
      'attachment_download_content_types' => ''
    )
    yield
  ensure
    Setting.plugin_redmine_gtt_fiware = saved
  end
end
