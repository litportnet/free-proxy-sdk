<!-- shared-readme:banner:start -->
[![Litport free proxies: live lists, API and SDKs](https://raw.githubusercontent.com/litportnet/free-proxy-sdk/main/assets/free-proxy-banner-static.png)](https://litport.net/free-proxy)
<!-- shared-readme:banner:end -->

# Litport Free Proxy SDK for PHP

Dependency-free PHP 8.2+ client for Litport's verified HTTP, SOCKS4, and SOCKS5 snapshot. It reads the documented API snapshot and filters normalized records locally.

## Install

```sh
composer require litportnet/free-proxy-sdk
```

```php
use Litportnet\FreeProxy\{Client, Filters};

$proxies = (new Client())->pickBest(5, new Filters(
    protocol: 'socks5', country: 'us', maxLatencyMs: 500,
    minUptime7d: 90, minChecks7d: 50, checkedWithinMin: 30,
));
```

`getProxies()` returns normalized immutable `Proxy` records sorted by seven-day uptime, latency, then URL. `pickBest()` returns the top matching records. Filters support protocol, country, anonymity, HTTPS, maximum latency, minimum seven-day uptime, minimum checks, freshness (1–1,440 minutes), and limit. A seven-day uptime is `null` when fewer than 50 checks were recorded.

The client validates the API envelope (`count`, `truncated`, and a `generatedAt` within two minutes), proxy addresses, and nullable values. Configure the timeout with `new Client(timeout: 5.0)`. Supply a callable transport `(string $url, array $headers, float $timeout): array` for deterministic tests.

## Test

```sh
composer install --no-interaction --prefer-dist
composer test
```

## Resources

- [Free proxy list](https://litport.net/free-proxy)
- [API documentation](https://litport.net/docs/free-proxy-api)
- [SDK source](https://github.com/litportnet/free-proxy-php)

Free proxies are for testing only. Never route credentials, cookies, payment data, or private data through them.
