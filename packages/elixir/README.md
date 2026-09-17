<!-- shared-readme:banner:start -->
[![Litport free proxies: live lists, API and SDKs](https://raw.githubusercontent.com/litportnet/free-proxy-sdk/main/assets/free-proxy-banner-static.png)](https://litport.net/free-proxy)
<!-- shared-readme:banner:end -->

# Litport Free Proxy SDK for Elixir

Elixir client for Litport's public snapshot of verified HTTP, SOCKS4, and SOCKS5 proxies. It uses only Erlang's built-in `:httpc` for HTTP and requires no API key.

## Install

```elixir
def deps do
  [
    {:litportnet_free_proxy, "~> 0.1"}
  ]
end
```

## Usage

```elixir
{:ok, client} = Litportnet.FreeProxy.new()

{:ok, proxies} =
  Litportnet.FreeProxy.get_proxies(client,
    protocol: "socks5",
    country: "us",
    max_latency_ms: 500,
    min_uptime_7d: 90,
    min_checks_7d: 50,
    checked_within_min: 30
  )

Enum.each(proxies, &IO.puts(&1.url))

{:ok, best} = Litportnet.FreeProxy.pick_best(client, 5, protocol: "http")
```

`get_proxies/2` and `pick_best/3` return normalized `Litportnet.FreeProxy.Proxy` structs. Filters accept protocol, country, anonymity, HTTPS, maximum latency, minimum seven-day uptime, minimum checks, freshness (1-1,440 minutes), and limit. Results sort by seven-day uptime, latency, then URL. `uptime_7d` is `nil` when a record has fewer than 50 checks.

The API envelope validates `count`, `truncated`, a two-minute `generatedAt` window, public IPv4 addresses, and nullable fields. Set `timeout:` on `new/1`; provide `transport: fn url, timeout -> {:ok, status, headers, body} end` for deterministic tests.

## Test

```sh
mix test
```

## Resources

- [Free proxy list](https://litport.net/free-proxy)
- [API documentation](https://litport.net/docs/free-proxy-api)
- [SDK source](https://github.com/litportnet/free-proxy-sdk)

Free proxies are for testing only. Never route credentials, cookies, payment data, or private data through them.
