[![Litport free proxies: live lists, API and SDKs](https://raw.githubusercontent.com/litportnet/free-proxy-sdk/main/assets/free-proxy-banner-static.png)](https://litport.net/free-proxy)

# litportnet-free-proxy-sdk

Typed Rust client for Litport's verified HTTP, SOCKS4, and SOCKS5 proxy snapshots.

## Install

```toml
[dependencies]
litportnet-free-proxy-sdk = "0.1"
```

## Use from Rust

```rust,no_run
use litportnet_free_proxy_sdk::{Client, Filters, Protocol};

let client = Client::new();
let filters = Filters::default()
    .protocol(Protocol::Socks5)
    .max_latency_ms(500)
    .min_uptime_7d(90)
    .checked_within_min(30);
let proxies = client.pick_best(5, &filters)?;

for proxy in proxies {
    println!("{}", proxy.proxy_url());
}
# Ok::<(), litportnet_free_proxy_sdk::Error>(())
```

`Client::get_proxies`, `Client::pick_best`, and `Client::rotate` return normalized `Proxy` values. `to_proxy_url` and `Proxy::proxy_url` format a value as `protocol://ip:port`.

## Sources and freshness

The API source is used by default:

`https://litport.net/api/free-proxy/snapshot?checkedWithinMin=1440`

Use `Client::builder().source(Source::Github)` for the optional [free-proxy-list dataset](https://github.com/litportnet/free-proxy-list). Each call applies a local `last_checked` freshness filter. It defaults to 30 minutes and accepts 1 through 1,440 minutes. API snapshots require `generatedAt` to be at most two minutes old and at most five seconds in the future. Seven-day uptime is omitted when fewer than 50 checks were recorded.

Responses remain in memory for no more than 60 seconds and revalidate with ETags. `ClientBuilder` accepts a custom `Transport` and `Clock` for deterministic tests.

## Safety

Free proxies are for testing only. Never send passwords, API keys, cookies, personal data, or payment data through them. For real workloads, use affordable [Litport proxies](https://litport.net).

## Resources

- [Free proxy list](https://litport.net/free-proxy)
- [API documentation](https://litport.net/docs/free-proxy-api)
- [Data repository](https://github.com/litportnet/free-proxy-list)
- [SDK repository](https://github.com/litportnet/free-proxy-sdk)
