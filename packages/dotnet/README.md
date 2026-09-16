<!-- shared-readme:banner:start -->
[![Litport free proxies: live lists, API and SDKs](https://raw.githubusercontent.com/litportnet/free-proxy-sdk/main/assets/free-proxy-banner-static.png)](https://litport.net/free-proxy)
<!-- shared-readme:banner:end -->

# Litport Free Proxy SDK for .NET

`Litportnet.FreeProxy` is a dependency-free `net8.0` client for Litport's documented API snapshot of verified HTTP, SOCKS4, and SOCKS5 proxies.

## Install

```sh
dotnet add package Litportnet.FreeProxy
```

```csharp
using Litportnet.FreeProxy;
using var client = new Client();
var proxies = await client.PickBestAsync(5, new Filters(Protocol: "socks5", Country: "us", MaxLatencyMs: 500, MinUptime7d: 90, MinChecks7d: 50, CheckedWithinMin: 30));
```

`GetProxiesAsync` and `PickBestAsync` return typed `Proxy` records. Filters support protocol, country, anonymity, HTTPS, maximum latency, minimum seven-day uptime, minimum checks, freshness (1–1,440 minutes), and limit. Records are ordered by seven-day uptime, latency, then URL. `Uptime7d` is `null` when fewer than 50 checks were recorded.

The client validates API `count`, `truncated`, and a two-minute `generatedAt` window, public IPv4 addresses, and nullable fields. Pass an `HttpMessageHandler` to `Client` for deterministic tests and set the request timeout with `timeout:`.

## Build and test

```sh
dotnet run --project tests/Litportnet.FreeProxy.Tests
dotnet pack src/Litportnet.FreeProxy --configuration Release
```

## Resources

- [Free proxy list](https://litport.net/free-proxy)
- [API documentation](https://litport.net/docs/free-proxy-api)
- [SDK source](https://github.com/litportnet/free-proxy-sdk)

Free proxies are for testing only. Never route credentials, cookies, payment data, or private data through them.
