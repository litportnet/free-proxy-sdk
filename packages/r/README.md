<!-- shared-readme:banner:start -->
[![Litport free proxies: live lists, API and SDKs](https://raw.githubusercontent.com/litportnet/free-proxy-sdk/main/assets/free-proxy-banner-static.png)](https://litport.net/free-proxy)
<!-- shared-readme:banner:end -->

# Litport Free Proxy SDK for R

R client for Litport's API snapshot of verified HTTP, SOCKS4, and SOCKS5 proxies, built on `curl` and `jsonlite`.

## Install

```r
install.packages("litportFreeProxy", repos = c("https://litportnet.r-universe.dev", "https://cloud.r-project.org"))
```

```r
library(litportFreeProxy)

client <- litport_client()
proxies <- pick_best(client, 5, protocol = "socks5", country = "us",
  max_latency_ms = 500, min_uptime_7d = 90, min_checks_7d = 50,
  checked_within_min = 30)
print(proxies$url)
```

`get_proxies()` and `pick_best()` return a normalized `data.frame`. Filters accept protocol, country, anonymity, HTTPS, maximum latency, minimum seven-day uptime, minimum checks, freshness (1-1,440 minutes), and limit. Results sort by seven-day uptime, latency, then URL. `uptime_7d` is `NA` when a record has fewer than 50 checks.

The API envelope validates `count`, `truncated`, a two-minute `generatedAt` window, public IPv4 addresses, and nullable fields. Set `timeout` on `litport_client()`; provide `transport = function(url, timeout) list(status, headers, body)` for deterministic tests.

## Test

```r
testthat::test_dir("tests/testthat")
```

## Resources

- [Free proxy list](https://litport.net/free-proxy)
- [API documentation](https://litport.net/docs/free-proxy-api)
- [SDK source](https://github.com/litportnet/free-proxy-sdk)

Free proxies are for testing only. Never route credentials, cookies, payment data, or private data through them.
