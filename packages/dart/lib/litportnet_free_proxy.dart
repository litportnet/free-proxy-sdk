/// A dependency-free Dart client for Litport's free-proxy API snapshot of
/// verified HTTP, SOCKS4, and SOCKS5 proxies.
///
/// This client only retrieves and filters proxy records; it never opens a
/// connection through a proxy and never routes any traffic on your behalf.
/// Free proxies are for testing only — never route credentials, cookies,
/// payment data, or private data through them.
///
/// ## Usage
///
/// ```dart
/// import 'package:litportnet_free_proxy/litportnet_free_proxy.dart';
///
/// Future<void> main() async {
///   final client = LitportFreeProxyClient();
///   final proxies = await client.pickBest(
///     5,
///     const ProxyFilters(
///       protocol: 'socks5',
///       country: 'us',
///       maxLatencyMs: 500,
///       minUptime7d: 90,
///       minChecks7d: 50,
///       checkedWithinMin: 30,
///     ),
///   );
///   for (final proxy in proxies) {
///     print(proxy.url);
///   }
///   client.close();
/// }
/// ```
///
/// [LitportFreeProxyClient.getProxies] and
/// [LitportFreeProxyClient.pickBest] return normalized [FreeProxy]
/// records. [ProxyFilters] accepts a protocol, country, anonymity level,
/// HTTPS support, maximum latency, minimum seven-day uptime, minimum
/// seven-day checks, a freshness window (`checkedWithinMin`, 1 to 1,440
/// minutes), and a result limit. Results are sorted by seven-day uptime
/// (descending), then latency (ascending), then URL. `uptime7d` is `null`
/// when a record has fewer than 50 checks in the last seven days.
///
/// See the [free proxy list](https://litport.net/free-proxy) and the
/// [API documentation](https://litport.net/docs/free-proxy-api) for
/// details on the underlying snapshot format.
library;

export 'src/client.dart';
export 'src/exceptions.dart';
export 'src/filters.dart';
export 'src/proxy.dart';
