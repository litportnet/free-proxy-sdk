/// Immutable filter criteria for [LitportFreeProxyClient.getProxies] (from
/// `client.dart`) and [LitportFreeProxyClient.pickBest].
///
/// Every field is optional; a `null` field does not filter. Numeric fields
/// must be non-negative integers when provided, and validation happens
/// inside `LitportFreeProxyClient`.
class ProxyFilters {
  /// Keep only proxies using this protocol: `http`, `socks4`, or `socks5`.
  final String? protocol;

  /// Keep only proxies whose two-letter country code matches, case
  /// insensitively.
  final String? country;

  /// Keep only proxies with this anonymity level: `transparent`,
  /// `anonymous`, `elite`, or `unknown`.
  final String? anonymity;

  /// Keep only proxies that do (`true`) or do not (`false`) support
  /// HTTPS.
  final bool? https;

  /// Keep only proxies with a known latency at or below this many
  /// milliseconds.
  final int? maxLatencyMs;

  /// Keep only proxies with a known seven-day uptime percentage at or
  /// above this value.
  final int? minUptime7d;

  /// Keep only proxies with at least this many checks in the last seven
  /// days.
  final int? minChecks7d;

  /// The maximum number of proxies to return, applied after sorting.
  final int? limit;

  /// Keep only proxies last checked within this many minutes of now.
  ///
  /// Defaults to 30 when `null`; must be from 1 to 1440 (24 hours)
  /// once defaulted.
  final int? checkedWithinMin;

  /// Creates an immutable set of proxy filters.
  const ProxyFilters({
    this.protocol,
    this.country,
    this.anonymity,
    this.https,
    this.maxLatencyMs,
    this.minUptime7d,
    this.minChecks7d,
    this.limit,
    this.checkedWithinMin,
  });
}
