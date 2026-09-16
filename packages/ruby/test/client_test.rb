# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require 'litportnet/free_proxy_sdk'

class FreeProxySdkTest < Minitest::Test
  NOW = -> { Time.iso8601('2026-09-10T00:00:00Z') }

  def fixture
    JSON.parse(File.read(File.join(__dir__, 'fixtures', 'api-snapshot.json')))
  end

  def client(body = fixture, status = 200, &block)
    Litportnet::FreeProxySdk::Client.new(now: NOW, transport: block || ->(_url, _headers, _timeout) { [status, {}, body] })
  end

  def test_normalizes_filters_and_nullable_uptime
    rows = client.get_proxies
    assert_equal 2, rows.length
    assert_equal 'http://8.8.8.8:8080', rows.first.url
    assert_equal 120, rows.first.latency_ms
    assert_equal 15_169, rows.first.asn
    assert_nil rows.last.uptime_7d
    assert_equal 1, client.get_proxies(protocol: 'socks5').length
    assert_equal 1, client.get_proxies(min_uptime_7d: 90).length
    assert_equal 1, client.pick_best(1).length
  end

  def test_rejects_bad_envelopes_and_http_errors
    assert_raises(Litportnet::FreeProxySdk::HttpError) { client([], 429).get_proxies }
    assert_raises(Litportnet::FreeProxySdk::SnapshotTruncatedError) { client({ 'generatedAt' => '2026-09-10T00:00:00Z', 'count' => 0, 'truncated' => true, 'proxies' => [] }).get_proxies }
    assert_raises(Litportnet::FreeProxySdk::SnapshotValidationError) { client({ 'generatedAt' => '2026-09-09T23:57:00Z', 'count' => 0, 'proxies' => [] }).get_proxies }
    invalid = fixture; invalid['proxies'][0]['host'] = '127.0.0.1'
    assert_raises(Litportnet::FreeProxySdk::SnapshotValidationError) { client(invalid).get_proxies }
  end

  def test_transport_receives_timeout_and_can_report_timeout
    received = nil
    timeout_client = Litportnet::FreeProxySdk::Client.new(timeout: 1.5, now: NOW, transport: lambda { |_url, _headers, timeout|
      received = timeout
      raise Litportnet::FreeProxySdk::TimeoutError, 'Snapshot request timed out after 1.5s'
    })
    assert_raises(Litportnet::FreeProxySdk::TimeoutError) { timeout_client.get_proxies }
    assert_equal 1.5, received
  end
  def test_malformed_fields_and_filter_boundaries
    assert_empty client.get_proxies(limit: 0)
    assert_equal 1, client.get_proxies(country: 'US').length
    {'host' => nil, 'port' => '8080', 'asn' => true, 'geoCountry' => 123, 'responseTimeMs' => Float::INFINITY,
     'pingAt' => '2026-09-10T00:00:00', 'createdAt' => '2026-02-30T00:00:00Z'}.each do |key, value|
      invalid = fixture; invalid['proxies'][0][key] = value
      assert_raises(Litportnet::FreeProxySdk::SnapshotValidationError, key) { client(invalid).get_proxies }
    end
    {'count' => 99, 'generatedAt' => '2026-09-10T00:00:06Z'}.each do |key, value|
      invalid = fixture; invalid[key] = value
      assert_raises(Litportnet::FreeProxySdk::SnapshotValidationError, key) { client(invalid).get_proxies }
    end
    [{https: 'yes'}, {protocol: false}, {checked_within_min: false}, {limit: -1}, {unknown: 1}].each do |filters|
      assert_raises(Litportnet::FreeProxySdk::FilterValidationError) { client.get_proxies(filters) }
    end
    invalid = fixture; invalid['proxies'][0]['pingAt'] = '2026-09-09T23:29:59Z'
    assert_equal 1, client(invalid).get_proxies.length
    assert_raises(Litportnet::FreeProxySdk::SnapshotValidationError) { client('{broken').get_proxies }
  end

end
