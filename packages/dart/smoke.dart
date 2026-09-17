// Live smoke check against the real snapshot API. Excluded from the published
// package, it exists so CI exercises the real HttpClient + TLS path that the
// offline test suite deliberately never touches.
import 'dart:io';

import 'package:litportnet_free_proxy/litportnet_free_proxy.dart';

Future<void> main() async {
  final client = LitportFreeProxyClient(timeout: const Duration(seconds: 20));
  try {
    final proxies = await client.pickBest(
      3,
      const ProxyFilters(protocol: 'socks5', checkedWithinMin: 1440),
    );
    stdout.writeln('live smoke: ${proxies.length} proxies');
    for (final proxy in proxies) {
      stdout.writeln('  ${proxy.url} uptime7d=${proxy.uptime7d} '
          'latencyMs=${proxy.latencyMs}');
    }
    if (proxies.isEmpty) exitCode = 1;
  } catch (error) {
    stdout.writeln('live smoke failed: $error');
    exitCode = 1;
  } finally {
    client.close();
  }
}
