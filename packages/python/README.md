<!-- shared-readme:banner:start -->
[![Litport free proxies: live lists, API and SDKs](https://raw.githubusercontent.com/litportnet/free-proxy-sdk/main/assets/free-proxy-banner-static.png)](https://litport.net/free-proxy)
<!-- shared-readme:banner:end -->

# litportnet-free-proxy-sdk

<!-- shared-readme:intro:start -->
[Browse the free proxy list](https://litport.net/free-proxy).

- Verified HTTP, SOCKS4, and SOCKS5 proxy records.
- Filter by freshness, latency, uptime, country, anonymity, and HTTPS support.
- Use the API or GitHub dataset through typed clients and CLIs.
<!-- shared-readme:intro:end -->

Dependency-free, typed Python 3.9+ client and CLI to discover and filter Litport's verified HTTP, SOCKS4, and SOCKS5 proxy records by freshness, latency, and uptime.

## Install

```sh
pip install litportnet-free-proxy-sdk
```

## Use from Python

```python
from litportnet_free_proxy_sdk import pick_best, to_proxy_url

proxies = pick_best(5, {
    "protocol": "socks5",
    "country": "us",
    "max_latency_ms": 500,
    "min_uptime_7d": 90,
    "min_checks_7d": 50,
    "checked_within_min": 30,
})

print([to_proxy_url(proxy) for proxy in proxies])
```

`get_proxies`, `pick_best`, and `rotate` return normalized `Proxy` records. `to_proxy_url(proxy)` formats a record as `protocol://ip:port`; `to_requests_proxies(proxy)` and `to_httpx_proxy(proxy)` return configuration values for those caller-installed libraries.

## CLI

```sh
litportnet-free-proxies \
  --protocol socks5 --country us --max-latency-ms 500 \
  --min-uptime7d 90 --min-checks7d 50 --limit 20 --format json
```

Filters are `--source api|github`, `--protocol http|socks4|socks5`, `--country`, `--anonymity`, `--https true|false`, `--max-latency-ms`, `--min-uptime7d`, `--min-checks7d`, `--checked-within-min`, and `--limit`. Choose `--format txt` for one `protocol://ip:port` value per line, `json` for normalized records, or `csv` for records with a header row.

The command exits with `0` when it writes matching records, `2` when no records match, and `1` for invalid options, validation failures, or snapshot request errors. Errors go to stderr.

## Sources and freshness

The default source is the Litport API snapshot:

`https://litport.net/api/free-proxy/snapshot?checkedWithinMin=1440`

Pass `source="github"` to `Client(...)`, or `--source github` to the CLI, to read the optional [free-proxy-list dataset](https://github.com/litportnet/free-proxy-list) instead. The API source validates that its `generatedAt` timestamp is no more than two minutes old and no more than five seconds in the future. Both sources apply a local `last_checked` freshness filter on every call; it defaults to 30 minutes and accepts 1 through 1,440 minutes. Records with fewer than 50 checks in seven days report no seven-day uptime value.

Responses are cached in memory, revalidated with ETags, and retained for at most 60 seconds. The client does not retry failed snapshot requests or return stale data after a failure.

<!-- shared-readme:safety:start -->
## Safety

Free proxies are for testing only. Never send passwords, API keys, cookies, personal data, or payment data through them. For real workloads, use affordable [Litport proxies](https://litport.net).
<!-- shared-readme:safety:end -->

<!-- shared-readme:resources:start -->
## Resources

- [Free proxy list](https://litport.net/free-proxy)
- [API documentation](https://litport.net/docs/free-proxy-api)
- [Data repository](https://github.com/litportnet/free-proxy-list)
- [SDK repository](https://github.com/litportnet/free-proxy-sdk)
<!-- shared-readme:resources:end -->
