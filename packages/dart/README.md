<!-- shared-readme:banner:start -->
[![Litport free proxies: live lists, API and SDKs](https://raw.githubusercontent.com/litportnet/free-proxy-sdk/main/assets/free-proxy-banner-static.png)](https://litport.net/free-proxy)
<!-- shared-readme:banner:end -->

# Litport Free Proxy SDK for Dart

Dependency-free Dart 3.4+ client for Litport's API snapshot of verified HTTP, SOCKS4, and SOCKS5 proxies.

## Install

```sh
dart pub add litportnet_free_proxy
```

```dart
import 'package:litportnet_free_proxy/litportnet_free_proxy.dart';

Future<void> main() async {
  final client = LitportFreeProxyClient();
  final proxies = await client.pickBest(
    5,
    const ProxyFilters(
      protocol: 'socks5',
      country: 'us',
      maxLatencyMs: 500,
      minUptime7d: 90,
      minChecks7d: 50,
      checkedWithinMin: 30,
    ),
  );
  for (final proxy in proxies) {
    print(proxy.url);
  }
  client.close();
}
```

`getProxies` and `pickBest` return normalized `FreeProxy` records. `ProxyFilters` accepts protocol, country, anonymity, HTTPS, maximum latency, minimum seven-day uptime, minimum checks, freshness (1–1,440 minutes), and limit. Results sort by seven-day uptime, latency, then URL. `uptime7d` is `null` when a record has fewer than 50 checks.

The API envelope validates `count`, `truncated`, a two-minute `generatedAt` window, public IPv4 addresses, and nullable fields. Set `timeout:` on `LitportFreeProxyClient`; provide `transport: (url, timeout) async => TransportResponse(...)` for deterministic tests.

## Test

```sh
dart test
dart analyze
```

## Resources

- [Free proxy list](https://litport.net/free-proxy)
- [API documentation](https://litport.net/docs/free-proxy-api)
- [SDK source](https://github.com/litportnet/free-proxy-sdk)

Free proxies are for testing only. Never route credentials, cookies, payment data, or private data through them.
