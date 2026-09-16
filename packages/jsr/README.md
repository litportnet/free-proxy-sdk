[![Litport free proxies: latest published counts, protocol chart, API and SDKs](https://raw.githubusercontent.com/litportnet/free-proxy-list/live/proxies/banner.svg)](https://litport.net/free-proxy)

# Litport free proxy SDK for JSR

Use `@litportnet/free-proxy-sdk` to retrieve and filter the verified [Litport free proxy list](https://litport.net/free-proxy) in Deno or other JSR-compatible runtimes.

```ts
import { pickBest, toProxyUrl } from '@litportnet/free-proxy-sdk'

const proxies = await pickBest(5, { protocol: 'socks5', checkedWithinMin: 30 })
console.log(proxies.map(toProxyUrl))
```

The default source is the Litport snapshot API. Pass `{ source: 'github' }` to `Client` to use the [free-proxy-list dataset](https://github.com/litportnet/free-proxy-list). API details are in the [free proxy documentation](https://litport.net/docs/free-proxy-api).

## Testing only

Free proxies are for testing only. Never route passwords, API keys, cookies, personal data, payment data, or production traffic through them. For real workloads, use [Litport proxies](https://litport.net).
