# frozen_string_literal: true

require 'json'
require 'net/http'
require 'time'
require 'date'
require 'ipaddr'

module Litportnet
  module FreeProxySdk
    DEFAULT_API_URL = 'https://litport.net/api/free-proxy/snapshot?checkedWithinMin=1440'
    PROTOCOLS = %w[http socks4 socks5].freeze
    ANONYMITY = %w[transparent anonymous elite unknown].freeze
    BLOCKED_RANGES = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4].map { IPAddr.new(_1) }.freeze

    class Error < StandardError; end
    class TimeoutError < Error; end
    class HttpError < Error
      attr_reader :status
      def initialize(status) = (@status = status; super("Snapshot request failed with HTTP #{status}"))
    end
    class SnapshotValidationError < Error; end
    class SnapshotTruncatedError < Error; end
    class FilterValidationError < Error; end

    Proxy = Struct.new(:protocol, :ip, :port, :url, :country, :region, :city, :timezone, :asn, :asn_org, :anonymity, :https, :latency_ms, :latency_median_ms, :uptime_24h, :uptime_7d, :checks_7d, :exit_ip, :sources_count, :first_seen, :last_checked, keyword_init: true) do
      def proxy_url = url
    end
    Filters = Struct.new(:protocol, :country, :anonymity, :https, :max_latency_ms, :min_uptime_7d, :min_checks_7d, :checked_within_min, :limit, keyword_init: true)

    class Client
      def initialize(api_url: DEFAULT_API_URL, timeout: 10, transport: nil, now: -> { Time.now.utc })
        raise FilterValidationError, 'timeout must be a positive finite number' unless timeout.is_a?(Numeric) && timeout.finite? && timeout.positive?
        @api_url, @timeout, @transport, @now = api_url, timeout.to_f, transport, now
      end

      def get_proxies(filters = nil)
        filters = validate_filters(filters)
        status, _headers, body = request
        raise HttpError, status unless (200..299).cover?(status)
        snapshot = body.is_a?(Hash) ? body : JSON.parse(body)
        raise SnapshotValidationError, 'Malformed snapshot envelope' unless snapshot.is_a?(Hash) && snapshot['proxies'].is_a?(Array)
        raise SnapshotTruncatedError, 'Snapshot is truncated' if snapshot['truncated'] == true
        unless snapshot['count'].is_a?(Integer) && snapshot['count'] == snapshot['proxies'].length && (!snapshot.key?('truncated') || [true, false].include?(snapshot['truncated']))
          raise SnapshotValidationError, 'Malformed snapshot envelope'
        end
        validate_generated_at(snapshot['generatedAt'])
        now, cutoff = @now.call, @now.call - filters.checked_within_min * 60
        rows = snapshot['proxies'].map { map_row(_1) }.select do |row|
          checked = parse_time(row.last_checked)
          checked >= cutoff && checked <= now + 5 && matches?(row, filters)
        end
        rows.sort_by { |row| [row.uptime_7d.nil? ? 1 : 0, -(row.uptime_7d || 0), row.latency_ms.nil? ? 1 : 0, row.latency_ms || 0, row.url] }.first(filters.limit || rows.length)
      rescue JSON::ParserError
        raise SnapshotValidationError, 'Malformed snapshot JSON'
      end

      def pick_best(count, filters = nil)
        raise FilterValidationError, 'count must be a non-negative integer' unless count.is_a?(Integer) && count >= 0
        get_proxies(filters).first(count)
      end

      private

      def request
        return @transport.call(@api_url, {}, @timeout) if @transport
        uri = URI(@api_url)
        http = Net::HTTP.new(uri.host, uri.port); http.use_ssl = uri.scheme == 'https'; http.open_timeout = @timeout; http.read_timeout = @timeout
        response = http.get(uri.request_uri)
        [response.code.to_i, response.each_header.to_h, response.body]
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
        raise TimeoutError, "Snapshot request timed out after #{@timeout}s"
      end

      def validate_filters(input)
        filters = input.is_a?(Filters) ? input : Filters.new(**(input || {}))
        raise FilterValidationError, 'protocol must be http, socks4, or socks5' if !filters.protocol.nil? && !PROTOCOLS.include?(filters.protocol)
        raise FilterValidationError, 'country must be a two-letter code' if !filters.country.nil? && (!filters.country.is_a?(String) || !/\A[a-zA-Z]{2}\z/.match?(filters.country))
        raise FilterValidationError, 'Invalid anonymity value' if !filters.anonymity.nil? && !ANONYMITY.include?(filters.anonymity)
        raise FilterValidationError, 'https must be boolean' unless filters.https.nil? || [true, false].include?(filters.https)
        %i[max_latency_ms min_uptime_7d min_checks_7d limit].each { |name| raise FilterValidationError, "#{name} must be a non-negative integer" if !filters[name].nil? && (!filters[name].is_a?(Integer) || filters[name] < 0) }
        minutes = filters.checked_within_min.nil? ? 30 : filters.checked_within_min
        raise FilterValidationError, 'checked_within_min must be from 1 to 1440' unless minutes.is_a?(Integer) && (1..1440).cover?(minutes)
        Filters.new(**filters.to_h.merge(country: filters.country&.downcase, checked_within_min: minutes))
      rescue ArgumentError
        raise FilterValidationError, 'Invalid filters'
      end

      def map_row(row)
        raise SnapshotValidationError, 'Snapshot contains an invalid proxy row' unless row.is_a?(Hash)
        protocol, ip, port = row.values_at('protocol', 'host', 'port')
        raise SnapshotValidationError, 'Snapshot contains an invalid proxy row' unless PROTOCOLS.include?(protocol) && public_ipv4?(ip) && port.is_a?(Integer) && (1..65_535).cover?(port) && ANONYMITY.include?(row['anonymity'])
        country, asn = row['geoCountry'], row['asn']
        raise SnapshotValidationError, 'Invalid country' unless country.nil? || (country.is_a?(String) && /\A[a-zA-Z]{2}\z/.match?(country))
        asn_match = asn.is_a?(String) ? /\AAS(\d+)\z/.match(asn) : nil
        asn = asn_match[1].to_i if asn_match
        raise SnapshotValidationError, 'Invalid ASN' unless asn.nil? || (asn.is_a?(Integer) && asn >= 0)
        %w[geoRegion geoCity geoTimezone asnOrgName externalIp].each { raise SnapshotValidationError, 'Invalid nullable string' unless row[_1].nil? || row[_1].is_a?(String) }
        raise SnapshotValidationError, 'Invalid https value' unless row['https'].nil? || [true, false].include?(row['https'])
        %w[responseTimeMs responseTimeMedianMs uptime24h uptime7d].each { raise SnapshotValidationError, 'Invalid nullable number' unless row[_1].nil? || (row[_1].is_a?(Numeric) && row[_1].finite?) }
        raise SnapshotValidationError, 'Invalid count' unless row['checks7d'].is_a?(Integer) && row['checks7d'] >= 0 && row['sourcesCount'].is_a?(Integer) && row['sourcesCount'] >= 0
        first, last = iso(row['createdAt']), iso(row['pingAt']); raise SnapshotValidationError, 'Invalid timestamp' unless first && last
        Proxy.new(protocol:, ip:, port:, url: "#{protocol}://#{ip}:#{port}", country: country&.downcase, region: row['geoRegion'], city: row['geoCity'], timezone: row['geoTimezone'], asn:, asn_org: row['asnOrgName'], anonymity: row['anonymity'], https: row['https'], latency_ms: row['responseTimeMs']&.round, latency_median_ms: row['responseTimeMedianMs']&.to_f, uptime_24h: row['uptime24h']&.to_f, uptime_7d: row['checks7d'] < 50 ? nil : row['uptime7d']&.to_f, checks_7d: row['checks7d'], exit_ip: row['externalIp'], sources_count: row['sourcesCount'], first_seen: first, last_checked: last)
      end

      def matches?(row, f)
        (f.protocol.nil? || row.protocol == f.protocol) && (f.country.nil? || row.country == f.country) && (f.anonymity.nil? || row.anonymity == f.anonymity) && (f.https.nil? || row.https == f.https) && (f.max_latency_ms.nil? || (!row.latency_ms.nil? && row.latency_ms <= f.max_latency_ms)) && (f.min_uptime_7d.nil? || (!row.uptime_7d.nil? && row.uptime_7d >= f.min_uptime_7d)) && (f.min_checks_7d.nil? || row.checks_7d >= f.min_checks_7d)
      end
      def validate_generated_at(value); time = parse_time(value); now = @now.call; raise SnapshotValidationError, 'Snapshot generatedAt is outside the accepted window' unless time && time <= now + 5 && time >= now - 120; end
      def iso(value); parse_time(value)&.iso8601(3); end
      def parse_time(value); return nil unless value.is_a?(String) && /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\z/.match?(value); return nil unless Date.valid_date?(*value[0, 10].split('-').map(&:to_i)); Time.iso8601(value).utc; rescue ArgumentError; nil; end
      def public_ipv4?(value); return false unless value.is_a?(String); ip = IPAddr.new(value); ip.ipv4? && BLOCKED_RANGES.none? { _1.include?(ip) }; rescue IPAddr::InvalidAddressError; false; end
    end
  end
end
