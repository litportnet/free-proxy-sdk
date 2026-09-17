import 'dart:convert';
import 'dart:io';

import 'exceptions.dart';
import 'filters.dart';
import 'proxy.dart';

const Set<String> _protocols = {'http', 'socks4', 'socks5'};
const Set<String> _anonymityLevels = {
  'transparent',
  'anonymous',
  'elite',
  'unknown',
};

final RegExp _countryCodePattern = RegExp(r'^[a-zA-Z]{2}$');
final RegExp _asnPattern = RegExp(r'^AS(\d+)$');
final RegExp _ipv4Pattern = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
final RegExp _timestampPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$',
);

/// A blocked IPv4 CIDR block, used to reject non-public addresses.
class _CidrBlock {
  final int network;
  final int prefixBits;

  const _CidrBlock(this.network, this.prefixBits);

  bool contains(int address) {
    final mask = (0xFFFFFFFF << (32 - prefixBits)) & 0xFFFFFFFF;
    return address & mask == network & mask;
  }
}

const List<_CidrBlock> _blockedRanges = <_CidrBlock>[
  _CidrBlock(0x00000000, 8), // 0.0.0.0/8
  _CidrBlock(0x0A000000, 8), // 10.0.0.0/8
  _CidrBlock(0x64400000, 10), // 100.64.0.0/10
  _CidrBlock(0x7F000000, 8), // 127.0.0.0/8
  _CidrBlock(0xA9FE0000, 16), // 169.254.0.0/16
  _CidrBlock(0xAC100000, 12), // 172.16.0.0/12
  _CidrBlock(0xC0000000, 24), // 192.0.0.0/24
  _CidrBlock(0xC0000200, 24), // 192.0.2.0/24
  _CidrBlock(0xC0A80000, 16), // 192.168.0.0/16
  _CidrBlock(0xC6120000, 15), // 198.18.0.0/15
  _CidrBlock(0xC6336400, 24), // 198.51.100.0/24
  _CidrBlock(0xCB007100, 24), // 203.0.113.0/24
  _CidrBlock(0xE0000000, 4), // 224.0.0.0/4
  _CidrBlock(0xF0000000, 4), // 240.0.0.0/4
];

/// The result of a single transport call: an HTTP status code, response
/// headers, and the raw response body.
///
/// Constructed by a custom `transport` callback passed to
/// [LitportFreeProxyClient], most commonly in tests.
class TransportResponse {
  /// The HTTP status code returned by the snapshot endpoint.
  final int statusCode;

  /// The response headers, keyed by header name.
  final Map<String, String> headers;

  /// The raw, not-yet-decoded response body.
  final String body;

  /// Creates a [TransportResponse].
  const TransportResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });
}

/// A client for retrieving and filtering Litport free-proxy snapshots.
///
/// The client only retrieves proxy records; it never opens a connection
/// through a proxy and never routes any traffic. Construct one client and
/// reuse it, then call [close] when done with it.
class LitportFreeProxyClient {
  /// The default Litport API snapshot endpoint, requesting rows checked
  /// within the last 24 hours.
  static final Uri defaultApiUrl = Uri.parse(
    'https://litport.net/api/free-proxy/snapshot?checkedWithinMin=1440',
  );

  final Uri _apiUrl;
  final Duration _timeout;
  final Future<TransportResponse> Function(Uri url, Duration timeout)?
      _transport;
  final DateTime Function() _now;
  HttpClient? _httpClient;

  /// Creates a client for the given [apiUrl], defaulting to
  /// [defaultApiUrl].
  ///
  /// [timeout] bounds each snapshot request and defaults to 10 seconds.
  /// Supply [transport] to replace the built-in `dart:io`-based HTTP
  /// transport, most commonly for deterministic tests. Supply [now] to
  /// control the clock used for freshness checks, also most commonly for
  /// tests.
  LitportFreeProxyClient({
    Uri? apiUrl,
    Duration timeout = const Duration(seconds: 10),
    Future<TransportResponse> Function(Uri url, Duration timeout)? transport,
    DateTime Function() now = _defaultNow,
  })  : _apiUrl = apiUrl ?? defaultApiUrl,
        _timeout = _requirePositiveTimeout(timeout),
        _transport = transport,
        _now = now;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  static Duration _requirePositiveTimeout(Duration timeout) {
    if (timeout <= Duration.zero) {
      throw const FilterValidationException(
        'timeout must be a positive duration',
      );
    }
    return timeout;
  }

  /// Retrieves the current snapshot and returns the proxies matching
  /// [filters], sorted with proxies that have a known seven-day uptime
  /// first (highest uptime first), then by ascending latency, then by
  /// URL. When [ProxyFilters.limit] is set, only the first `limit`
  /// results are returned.
  Future<List<FreeProxy>> getProxies([
    ProxyFilters filters = const ProxyFilters(),
  ]) async {
    final validated = _validateFilters(filters);
    final transport = _transport ?? _builtInTransport;
    final response = await transport(_apiUrl, _timeout);
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw HttpStatusException(response.statusCode);
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const SnapshotValidationException('Malformed snapshot JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const SnapshotValidationException(
        'Malformed snapshot envelope',
      );
    }
    final envelope = decoded;
    final rawProxies = envelope['proxies'];
    if (rawProxies is! List) {
      throw const SnapshotValidationException(
        'Malformed snapshot envelope',
      );
    }
    final proxiesJson = rawProxies;
    if (envelope['truncated'] == true) {
      throw const SnapshotTruncatedException();
    }
    final count = envelope['count'];
    final truncated = envelope['truncated'];
    if (count is! int ||
        count != proxiesJson.length ||
        (truncated != null && truncated is! bool)) {
      throw const SnapshotValidationException(
        'Malformed snapshot envelope',
      );
    }

    final now = _now();
    _validateGeneratedAt(envelope['generatedAt'], now);
    final checkedWithinMin = validated.checkedWithinMin!;
    final cutoff = now.subtract(Duration(minutes: checkedWithinMin));
    final freshnessLimit = now.add(const Duration(seconds: 5));

    final rows = <FreeProxy>[];
    for (final rawRow in proxiesJson) {
      final row = _mapRow(rawRow);
      final checked = row.lastChecked;
      if (checked.isBefore(cutoff) || checked.isAfter(freshnessLimit)) {
        continue;
      }
      if (_matches(row, validated)) {
        rows.add(row);
      }
    }
    rows.sort(_compareProxies);

    final limit = validated.limit;
    if (limit != null && limit < rows.length) {
      return rows.sublist(0, limit);
    }
    return rows;
  }

  /// Retrieves proxies matching [filters] and returns at most [count] of
  /// the top-ranked results.
  Future<List<FreeProxy>> pickBest(
    int count, [
    ProxyFilters filters = const ProxyFilters(),
  ]) async {
    if (count < 0) {
      throw const FilterValidationException(
        'count must be a non-negative integer',
      );
    }
    final rows = await getProxies(filters);
    return rows.length > count ? rows.sublist(0, count) : rows;
  }

  /// Closes the built-in HTTP transport, releasing any pooled
  /// connections. Safe to call even when a custom [transport] was
  /// supplied to the constructor, in which case it is a no-op.
  void close() {
    _httpClient?.close(force: true);
    _httpClient = null;
  }

  Future<TransportResponse> _builtInTransport(Uri url, Duration timeout) {
    final httpClient = _httpClient ??= HttpClient();
    httpClient.connectionTimeout = timeout;
    return _performRequest(httpClient, url).timeout(
      timeout,
      onTimeout: () => throw ProxyTimeoutException(
        'Snapshot request timed out after '
        '${timeout.inMilliseconds / 1000}s',
      ),
    );
  }

  static Future<TransportResponse> _performRequest(
    HttpClient httpClient,
    Uri url,
  ) async {
    final request = await httpClient.getUrl(url);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });
    return TransportResponse(
      statusCode: response.statusCode,
      headers: headers,
      body: body,
    );
  }
}

ProxyFilters _validateFilters(ProxyFilters filters) {
  if (filters.protocol != null && !_protocols.contains(filters.protocol)) {
    throw const FilterValidationException(
      'protocol must be http, socks4, or socks5',
    );
  }
  final country = filters.country;
  if (country != null && !_countryCodePattern.hasMatch(country)) {
    throw const FilterValidationException(
      'country must be a two-letter code',
    );
  }
  if (filters.anonymity != null &&
      !_anonymityLevels.contains(filters.anonymity)) {
    throw const FilterValidationException('Invalid anonymity value');
  }
  final nonNegative = <String, int?>{
    'maxLatencyMs': filters.maxLatencyMs,
    'minUptime7d': filters.minUptime7d,
    'minChecks7d': filters.minChecks7d,
    'limit': filters.limit,
  };
  for (final entry in nonNegative.entries) {
    final value = entry.value;
    if (value != null && value < 0) {
      throw FilterValidationException(
        '${entry.key} must be a non-negative integer',
      );
    }
  }
  final checkedWithinMin = filters.checkedWithinMin ?? 30;
  if (checkedWithinMin < 1 || checkedWithinMin > 1440) {
    throw const FilterValidationException(
      'checkedWithinMin must be from 1 to 1440',
    );
  }
  return ProxyFilters(
    protocol: filters.protocol,
    country: country?.toLowerCase(),
    anonymity: filters.anonymity,
    https: filters.https,
    maxLatencyMs: filters.maxLatencyMs,
    minUptime7d: filters.minUptime7d,
    minChecks7d: filters.minChecks7d,
    limit: filters.limit,
    checkedWithinMin: checkedWithinMin,
  );
}

bool _matches(FreeProxy row, ProxyFilters filters) {
  if (filters.protocol != null && row.protocol != filters.protocol) {
    return false;
  }
  if (filters.country != null && row.country != filters.country) {
    return false;
  }
  if (filters.anonymity != null && row.anonymity != filters.anonymity) {
    return false;
  }
  if (filters.https != null && row.https != filters.https) {
    return false;
  }
  final maxLatencyMs = filters.maxLatencyMs;
  if (maxLatencyMs != null &&
      (row.latencyMs == null || row.latencyMs! > maxLatencyMs)) {
    return false;
  }
  final minUptime7d = filters.minUptime7d;
  if (minUptime7d != null &&
      (row.uptime7d == null || row.uptime7d! < minUptime7d)) {
    return false;
  }
  final minChecks7d = filters.minChecks7d;
  if (minChecks7d != null && row.checks7d < minChecks7d) {
    return false;
  }
  return true;
}

int _compareProxies(FreeProxy a, FreeProxy b) {
  final aHasUptime = a.uptime7d != null;
  final bHasUptime = b.uptime7d != null;
  if (aHasUptime != bHasUptime) {
    return aHasUptime ? -1 : 1;
  }
  if (aHasUptime && a.uptime7d != b.uptime7d) {
    return b.uptime7d!.compareTo(a.uptime7d!);
  }
  final aHasLatency = a.latencyMs != null;
  final bHasLatency = b.latencyMs != null;
  if (aHasLatency != bHasLatency) {
    return aHasLatency ? -1 : 1;
  }
  if (aHasLatency && a.latencyMs != b.latencyMs) {
    return a.latencyMs!.compareTo(b.latencyMs!);
  }
  return a.url.compareTo(b.url);
}

void _validateGeneratedAt(dynamic value, DateTime now) {
  final parsed = _parseTimestamp(value);
  final earliest = now.subtract(const Duration(seconds: 120));
  final latest = now.add(const Duration(seconds: 5));
  if (parsed == null || parsed.isAfter(latest) || parsed.isBefore(earliest)) {
    throw const SnapshotValidationException(
      'Snapshot generatedAt is outside the accepted window',
    );
  }
}

FreeProxy _mapRow(dynamic raw) {
  if (raw is! Map<String, dynamic>) {
    throw const SnapshotValidationException(
      'Snapshot contains an invalid proxy row',
    );
  }

  final protocol = raw['protocol'];
  final ip = raw['host'];
  final port = raw['port'];
  final anonymity = raw['anonymity'];
  if (protocol is! String ||
      !_protocols.contains(protocol) ||
      ip is! String ||
      !_isPublicIpv4(ip) ||
      port is! int ||
      port < 1 ||
      port > 65535 ||
      anonymity is! String ||
      !_anonymityLevels.contains(anonymity)) {
    throw const SnapshotValidationException(
      'Snapshot contains an invalid proxy row',
    );
  }

  final rawCountry = raw['geoCountry'];
  if (rawCountry != null &&
      (rawCountry is! String || !_countryCodePattern.hasMatch(rawCountry))) {
    throw const SnapshotValidationException('Invalid country');
  }
  final country = (rawCountry as String?)?.toLowerCase();

  final asn = _mapAsn(raw['asn']);

  const nullableStringKeys = [
    'geoRegion',
    'geoCity',
    'geoTimezone',
    'asnOrgName',
    'externalIp',
  ];
  for (final key in nullableStringKeys) {
    final value = raw[key];
    if (value != null && value is! String) {
      throw const SnapshotValidationException('Invalid nullable string');
    }
  }

  final https = raw['https'];
  if (https != null && https is! bool) {
    throw const SnapshotValidationException('Invalid https value');
  }

  const nullableNumberKeys = [
    'responseTimeMs',
    'responseTimeMedianMs',
    'uptime24h',
    'uptime7d',
  ];
  for (final key in nullableNumberKeys) {
    final value = raw[key];
    if (value != null && !_isFiniteNumber(value)) {
      throw const SnapshotValidationException('Invalid nullable number');
    }
  }

  final checks7d = raw['checks7d'];
  final sourcesCount = raw['sourcesCount'];
  if (checks7d is! int ||
      checks7d < 0 ||
      sourcesCount is! int ||
      sourcesCount < 0) {
    throw const SnapshotValidationException('Invalid count');
  }

  final firstSeen = _parseTimestamp(raw['createdAt']);
  final lastChecked = _parseTimestamp(raw['pingAt']);
  if (firstSeen == null || lastChecked == null) {
    throw const SnapshotValidationException('Invalid timestamp');
  }

  final latencyMs = _toDouble(raw['responseTimeMs'])?.round();
  final uptime7d = checks7d < 50 ? null : _toDouble(raw['uptime7d']);

  return FreeProxy(
    protocol: protocol,
    ip: ip,
    port: port,
    url: '$protocol://$ip:$port',
    country: country,
    region: raw['geoRegion'] as String?,
    city: raw['geoCity'] as String?,
    timezone: raw['geoTimezone'] as String?,
    asn: asn,
    asnOrg: raw['asnOrgName'] as String?,
    anonymity: anonymity,
    https: https as bool?,
    latencyMs: latencyMs,
    latencyMedianMs: _toDouble(raw['responseTimeMedianMs']),
    uptime24h: _toDouble(raw['uptime24h']),
    uptime7d: uptime7d,
    checks7d: checks7d,
    exitIp: raw['externalIp'] as String?,
    sourcesCount: sourcesCount,
    firstSeen: firstSeen,
    lastChecked: lastChecked,
  );
}

int? _mapAsn(dynamic raw) {
  if (raw == null) {
    return null;
  }
  if (raw is int) {
    if (raw < 0) {
      throw const SnapshotValidationException('Invalid ASN');
    }
    return raw;
  }
  if (raw is String) {
    final match = _asnPattern.firstMatch(raw);
    if (match != null) {
      return int.parse(match.group(1)!);
    }
  }
  throw const SnapshotValidationException('Invalid ASN');
}

bool _isFiniteNumber(dynamic value) => value is num && value.isFinite;

/// Converts a nullable JSON number to a nullable [double]. Callers must
/// have already validated [value] as null-or-finite-number.
double? _toDouble(dynamic value) =>
    value == null ? null : (value as num).toDouble();

bool _isPublicIpv4(String value) {
  if (!_ipv4Pattern.hasMatch(value)) {
    return false;
  }
  var address = 0;
  for (final part in value.split('.')) {
    final octet = int.parse(part);
    if (octet > 255) {
      return false;
    }
    address = (address << 8) | octet;
  }
  for (final block in _blockedRanges) {
    if (block.contains(address)) {
      return false;
    }
  }
  return true;
}

bool _isLeapYear(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

bool _isValidCalendarDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1) {
    return false;
  }
  const daysInMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  var maxDay = daysInMonth[month - 1];
  if (month == 2 && _isLeapYear(year)) {
    maxDay = 29;
  }
  return day <= maxDay;
}

DateTime? _parseTimestamp(dynamic value) {
  if (value is! String || !_timestampPattern.hasMatch(value)) {
    return null;
  }
  final year = int.parse(value.substring(0, 4));
  final month = int.parse(value.substring(5, 7));
  final day = int.parse(value.substring(8, 10));
  if (!_isValidCalendarDate(year, month, day)) {
    return null;
  }
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    return null;
  }
}
