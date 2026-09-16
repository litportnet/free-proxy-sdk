# Container CLI

The container image packages the existing Node 24 CLI. It is a non-root command-line client, not a proxy server.

```sh
docker build -t litport-free-proxies .
docker run --rm litport-free-proxies --protocol socks5 --country us --limit 20 --format json
docker run --rm litport-free-proxies --source github --max-latency-ms 500 --format csv
```

The CLI retrieves the public snapshot when invoked and writes matching records to stdout. It accepts the same filters as the npm CLI; it does not listen on a port, relay traffic, or check proxies.

Free proxies are for testing only. Do not send secrets, personal data, payment data, or production traffic through them. Image builds require Docker-capable CI; Docker is intentionally not run during local SDK checks.
