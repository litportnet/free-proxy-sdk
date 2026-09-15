# @litportnet/free-proxy-sdk

Dependency-free, typed Node.js 20+ client and CLI to discover and filter Litport's verified HTTP, SOCKS4, and SOCKS5 proxy records by freshness, latency, and uptime.

## Install

```sh
npm install @litportnet/free-proxy-sdk
```

## Use from JavaScript

```js
import { pickBest, toProxyUrl } from '@litportnet/free-proxy-sdk'

const proxies = await pickBest(5, {
  protocol: 'socks5',
  country: 'us',
  maxLatencyMs: 500,
  minUptime7d: 90,
  minChecks7d: 50,
  checkedWithinMin: 30,
})

console.log(proxies.map(toProxyUrl))
```

`getProxies`, `pickBest`, and `rotate` return normalized proxy records. Use `toProxyUrl(proxy)` to format a record as `protocol://ip:port`. `withProxyAgent(proxy, ProxyAgentCtor)` creates an instance of an agent constructor that you provide.

## CLI

```sh
npx --package @litportnet/free-proxy-sdk litportnet-free-proxies \
  --protocol socks5 --country us --max-latency-ms 500 \
  --min-uptime7d 90 --min-checks7d 50 --limit 20 --format json
```

Filters are `--source api|github`, `--protocol http|socks4|socks5`, `--country`, `--anonymity`, `--https true|false`, `--max-latency-ms`, `--min-uptime7d`, `--min-checks7d`, `--checked-within-min`, and `--limit`. Choose `--format txt` for one `protocol://ip:port` value per line, `json` for normalized records, or `csv` for records with a header row.

The command exits with `0` when it writes matching records, `2` when no records match, and `1` for invalid options, validation failures, or snapshot request errors. Errors go to stderr.

## Sources and freshness

The default source is the Litport API snapshot:

`https://litport.net/api/free-proxy/snapshot?checkedWithinMin=1440`

Pass `{ source: 'github' }` to `new Client(...)`, or `--source github` to the CLI, to read the optional [free-proxy-list dataset](https://github.com/litportnet/free-proxy-list) instead. The API source validates that its `generatedAt` timestamp is no more than two minutes old and no more than five seconds in the future. Both sources apply a local `lastChecked` freshness filter on every call; it defaults to 30 minutes and accepts 1 through 1,440 minutes. Records with fewer than 50 checks in seven days report no seven-day uptime value.

Responses are cached in memory, revalidated with ETags, and retained for at most 60 seconds. The client does not retry failed snapshot requests or return stale data after a failure.

See the [API documentation](https://litport.net/docs/free-proxy-api), [data repository](https://github.com/litportnet/free-proxy-list), and [source repository](https://github.com/litportnet/free-proxy-sdk).
