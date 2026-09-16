[![Litport free proxies: latest published counts, protocol chart, API and SDKs](https://raw.githubusercontent.com/litportnet/free-proxy-list/live/proxies/banner.svg)](https://litport.net/free-proxy)

# Litport free proxy SDK

<!-- shared-readme:intro:start -->
[Browse the free proxy list](https://litport.net/free-proxy).

- Verified HTTP, SOCKS4, and SOCKS5 proxy records.
- Filter by freshness, latency, uptime, country, anonymity, and HTTPS support.
- Use the API or GitHub dataset through typed clients and CLIs.
<!-- shared-readme:intro:end -->

Dependency-free, typed JavaScript and Python clients plus CLIs to discover and filter Litport's verified HTTP, SOCKS4, and SOCKS5 proxy records by freshness, latency, and uptime.

```sh
npm install @litportnet/free-proxy-sdk
pip install litportnet-free-proxy-sdk
```

```js
import { pickBest, toProxyUrl } from '@litportnet/free-proxy-sdk'

const proxies = await pickBest(5, {
  protocol: 'socks5',
  maxLatencyMs: 500,
  minUptime7d: 90,
  checkedWithinMin: 30,
})
console.log(proxies.map(toProxyUrl))
```

```python
from litportnet_free_proxy_sdk import pick_best, to_proxy_url

proxies = pick_best(5, {
    "protocol": "socks5",
    "max_latency_ms": 500,
    "min_uptime_7d": 90,
    "checked_within_min": 30,
})
print([to_proxy_url(proxy) for proxy in proxies])
```

## More runtimes and tools

- [Go client](packages/go): standard-library module with context-aware requests.
- [Rust client](packages/rust): typed blocking client using rustls HTTPS.
- [JSR package](packages/jsr): native ESM JavaScript with TypeScript declarations.
- [Docker CLI](container): containerized JSON, CSV and text exports.
- [Postman and historical datasets](distribution): ready-to-run API requests and dated observation exports.

## Automation

The packages retrieve and normalize proxy records for selection in your automation. Filter by protocol, country, anonymity, HTTPS support, maximum latency, minimum seven-day uptime, minimum checks, and freshness; then use the returned records with the networking library you choose.

The default source is `https://litport.net/api/free-proxy/snapshot?checkedWithinMin=1440`. Each client applies its own 30-minute `lastChecked` freshness filter by default (configurable from 1 to 1,440 minutes), caches in memory for at most 60 seconds, and revalidates with ETags. Use JavaScript `{ source: 'github' }`, Python `source="github"`, or CLI `--source github` for the optional [free-proxy-list dataset](https://github.com/litportnet/free-proxy-list).

## CLI

```sh
npx --package @litportnet/free-proxy-sdk litportnet-free-proxies \
  --protocol socks5 --country us --max-latency-ms 500 --limit 20 --format json
litportnet-free-proxies \
  --protocol socks5 --country us --max-latency-ms 500 --limit 20 --format csv
```

The CLI accepts `--source`, `--protocol`, `--country`, `--anonymity`, `--https`, `--max-latency-ms`, `--min-uptime7d`, `--min-checks7d`, `--checked-within-min`, `--limit`, and `--format txt|json|csv`. It exits `0` after writing matches, `2` when no records match, and `1` for validation or request errors.

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

Read the package-specific guides for [JavaScript](packages/js/README.md) and [Python](packages/python/README.md). Contract mappings are in [spec/fields.json](spec/fields.json).

## Maintain shared README content

Edit the marked shared blocks in this README, then run `node scripts/sync-readmes.mjs`. Use `node scripts/sync-readmes.mjs --check` to verify the package READMEs are in sync.
