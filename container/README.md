[![Litport free proxies: live lists, API and SDKs](https://raw.githubusercontent.com/litportnet/free-proxy-sdk/main/assets/free-proxy-banner-static.png)](https://litport.net/free-proxy)

# Litport free proxy CLI

Find and filter HTTP, SOCKS4 and SOCKS5 proxy records from the [Litport free proxy list](https://litport.net/free-proxy). Export JSON, CSV or text for testing and automation without installing a local language runtime.

```sh
docker run --rm litportnet/free-proxy-sdk:0.1.0 --protocol socks5 --country us --limit 20 --format json
docker run --rm litportnet/free-proxy-sdk:0.1.0 --source github --max-latency-ms 500 --format csv
```

The image runs the Node 24 CLI as a non-root user and writes matching records to stdout. It accepts filters for country, protocol, anonymity, HTTPS support, latency, uptime, checks and freshness. It retrieves proxy records; it does not host a proxy server or forward application traffic. The published image currently supports Linux amd64.

See the [API documentation](https://litport.net/docs/free-proxy-api), [SDK source and CLI options](https://github.com/litportnet/free-proxy-sdk), and [public proxy dataset](https://github.com/litportnet/free-proxy-list).

Free proxies are for testing only. Never send credentials, personal data, payment data or production traffic through them. For real workloads use affordable [Litport proxies](https://litport.net).

To build from source, run `docker build -t litportnet/free-proxy-sdk:local .` from the SDK repository root.
