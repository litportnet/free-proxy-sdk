# Live smoke check against the real snapshot API. Excluded from the built
# package (see .Rbuildignore); it exists so CI exercises the real curl path that
# the offline test suite deliberately never touches.
library(litportFreeProxy)

client <- litport_client(timeout = 20)
proxies <- pick_best(client, 3, protocol = "socks5", checked_within_min = 1440)

cat(sprintf("live smoke: %d proxies\n", nrow(proxies)))
if (nrow(proxies) == 0) {
  stop("live smoke returned no proxies")
}
print(proxies[, c("url", "uptime_7d", "latency_ms", "country")])
