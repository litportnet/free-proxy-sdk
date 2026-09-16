<!-- shared-readme:banner:start -->
[![Litport free proxies: live lists, API and SDKs](https://raw.githubusercontent.com/litportnet/free-proxy-sdk/main/assets/free-proxy-banner-static.png)](https://litport.net/free-proxy)
<!-- shared-readme:banner:end -->

# free-proxy-sdk/go

[Browse the free proxy list](https://litport.net/free-proxy). This standard-library-only Go client reads verified HTTP, SOCKS4, and SOCKS5 proxy records from Litport's API or the optional GitHub dataset.

## Install

```sh
go get github.com/litportnet/free-proxy-sdk/packages/go@v0.1.0
```

## Use from Go

```go
package main

import (
	"context"
	"fmt"

	freeproxy "github.com/litportnet/free-proxy-sdk/packages/go"
)

func main() {
	client, err := freeproxy.NewClient(freeproxy.ClientOptions{})
	if err != nil {
		panic(err)
	}
	proxies, err := client.PickBest(context.Background(), 5, freeproxy.Filters{
		Protocol:         "socks5",
		Country:          "us",
		MaxLatencyMS:     freeproxy.Int(500),
		MinUptime7d:      freeproxy.Int(90),
		MinChecks7d:      freeproxy.Int(50),
		CheckedWithinMin: freeproxy.Int(30),
	})
	if err != nil {
		panic(err)
	}
	for _, proxy := range proxies {
		fmt.Println(freeproxy.ToProxyURL(proxy))
	}
}
```

`GetProxies`, `PickBest`, and `Rotate` return normalized `Proxy` records. `ToProxyURL(proxy)` formats a record as `protocol://ip:port`. Pass `Source: freeproxy.SourceGitHub` in `ClientOptions` to use the optional [free-proxy-list dataset](https://github.com/litportnet/free-proxy-list).

## Sources and freshness

The API source is the default: `https://litport.net/api/free-proxy/snapshot?checkedWithinMin=1440`. It verifies that `generatedAt` is no more than two minutes old and no more than five seconds in the future. Every call applies the local `lastChecked` freshness filter; it defaults to 30 minutes and accepts 1 through 1,440 minutes. Records with fewer than 50 checks in seven days report no seven-day uptime.

Responses are cached in memory, revalidated with ETags, and retained for at most 60 seconds. Requests respect the caller context and the client timeout. The client does not retry failed requests or return stale data after a failure.

## Safety

Free proxies are for testing only. Never send passwords, API keys, cookies, personal data, or payment data through them. For real workloads, use affordable [Litport proxies](https://litport.net).

## Resources

- [Free proxy list](https://litport.net/free-proxy)
- [API documentation](https://litport.net/docs/free-proxy-api)
- [SDK repository](https://github.com/litportnet/free-proxy-sdk)
