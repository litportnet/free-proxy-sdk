/// An immutable, normalized proxy record returned by
/// [LitportFreeProxyClient.getProxies] (from `client.dart`) and
/// [LitportFreeProxyClient.pickBest].
class FreeProxy {
  /// The proxy protocol: `http`, `socks4`, or `socks5`.
  final String protocol;

  /// The proxy's public IPv4 address.
  final String ip;

  /// The proxy's listening port, from 1 to 65535.
  final int port;

  /// The proxy URL, formatted as `protocol://ip:port`.
  final String url;

  /// The proxy's two-letter country code, lowercased, or `null` when
  /// unknown.
  final String? country;

  /// The proxy's region or state, or `null` when unknown.
  final String? region;

  /// The proxy's city, or `null` when unknown.
  final String? city;

  /// The proxy's IANA timezone name, or `null` when unknown.
  final String? timezone;

  /// The proxy's autonomous system number, or `null` when unknown.
  final int? asn;

  /// The proxy's autonomous system organization name, or `null` when
  /// unknown.
  final String? asnOrg;

  /// The proxy's anonymity level: `transparent`, `anonymous`, `elite`,
  /// or `unknown`.
  final String anonymity;

  /// Whether the proxy supports HTTPS, or `null` when unknown.
  final bool? https;

  /// The proxy's most recent latency in milliseconds, or `null` when
  /// unknown.
  final int? latencyMs;

  /// The proxy's median latency in milliseconds, or `null` when unknown.
  final double? latencyMedianMs;

  /// The proxy's uptime percentage over the last 24 hours, or `null`
  /// when unknown.
  final double? uptime24h;

  /// The proxy's uptime percentage over the last 7 days, or `null` when
  /// unknown, or when [checks7d] is below 50.
  final double? uptime7d;

  /// The number of checks performed against this proxy in the last 7
  /// days.
  final int checks7d;

  /// The externally observed exit IP address, or `null` when unknown.
  final String? exitIp;

  /// The number of independent sources that have reported this proxy.
  final int sourcesCount;

  /// When this proxy was first observed, in UTC.
  final DateTime firstSeen;

  /// When this proxy was last checked, in UTC.
  final DateTime lastChecked;

  /// Creates an immutable, normalized proxy record.
  const FreeProxy({
    required this.protocol,
    required this.ip,
    required this.port,
    required this.url,
    this.country,
    this.region,
    this.city,
    this.timezone,
    this.asn,
    this.asnOrg,
    required this.anonymity,
    this.https,
    this.latencyMs,
    this.latencyMedianMs,
    this.uptime24h,
    this.uptime7d,
    required this.checks7d,
    this.exitIp,
    required this.sourcesCount,
    required this.firstSeen,
    required this.lastChecked,
  });

  /// Returns [url].
  @override
  String toString() => url;

  /// Converts this record to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'protocol': protocol,
        'ip': ip,
        'port': port,
        'url': url,
        'country': country,
        'region': region,
        'city': city,
        'timezone': timezone,
        'asn': asn,
        'asnOrg': asnOrg,
        'anonymity': anonymity,
        'https': https,
        'latencyMs': latencyMs,
        'latencyMedianMs': latencyMedianMs,
        'uptime24h': uptime24h,
        'uptime7d': uptime7d,
        'checks7d': checks7d,
        'exitIp': exitIp,
        'sourcesCount': sourcesCount,
        'firstSeen': firstSeen.toIso8601String(),
        'lastChecked': lastChecked.toIso8601String(),
      };
}
