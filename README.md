# Litport free proxy SDK

Dependency-free JavaScript and Python clients for Litport's verified free-proxy snapshot.

```sh
npm install @litport/free-proxy-sdk
pip install litport-free-proxy-sdk
```

```js
import { pickBest, toProxyUrl } from '@litport/free-proxy-sdk'
console.log((await pickBest(1)).map(toProxyUrl))
```

```python
from litport_free_proxy_sdk import pick_best, to_proxy_url
print([to_proxy_url(proxy) for proxy in pick_best(1)])
```

Both clients use `https://litport.net/api/free-proxy/snapshot?checkedWithinMin=1440` by default. They cache only in memory, revalidate with ETags, cap cache lifetime at 60 seconds, and apply a 30-minute local freshness check on every call. Select `source="github"` (or `{ source: 'github' }`) to use the [free-proxy-list data repository](https://github.com/litportnet/free-proxy-list) instead.

The clients do not retry requests or return stale data after a failure. See the [API documentation](https://litport.net/docs/free-proxy-api) for source fields and [the data repository](https://github.com/litportnet/free-proxy-list) for how proxies are checked.

## CLI

```sh
npx @litport/free-proxy-sdk --protocol socks5 --country us --limit 20 --format txt
litport-free-proxies --protocol socks5 --country us --limit 20 --format json
```

The CLI supports `--source`, `--protocol`, `--country`, `--anonymity`, `--https`, `--max-latency-ms`, `--min-uptime7d`, `--min-checks7d`, `--checked-within-min`, `--limit`, and `--format txt|json|csv`. It exits 2 when no proxy matches and emits errors only to stderr.

`withProxyAgent(proxy, ProxyAgentCtor)` accepts a caller-provided JavaScript agent constructor. Protocol compatibility is the caller's responsibility. Python exposes `to_requests_proxies(proxy)` and `to_httpx_proxy(proxy)` as dependency-free configuration helpers.

This SDK requires Node.js 20+ or Python 3.9+. Contract mappings are in [spec/fields.json](spec/fields.json); version 1.0.0 requires the snapshot fields listed there.
