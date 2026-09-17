\name{litportFreeProxy-package}
\alias{litportFreeProxy-package}
\alias{litportFreeProxy}
\docType{package}
\title{litportFreeProxy: Client for the Litport Free Proxy Snapshot API}
\description{
Fetches and validates snapshots of verified HTTP, SOCKS4, and SOCKS5
proxies from the Litport free proxy API. Filters results by protocol,
country, anonymity, HTTPS support, latency, uptime, and freshness,
returning a normalized data frame. Validation rejects private and
reserved IPv4 ranges, malformed timestamps, and truncated or stale
snapshots.
}
\details{
Create a client with \code{\link{litport_client}}, then fetch proxies
with \code{\link{get_proxies}} or \code{\link{pick_best}}. Both functions
validate the snapshot envelope and every proxy row, raising conditions of
class \code{litport_error} (with a more specific subclass such as
\code{litport_http_error} or \code{litport_snapshot_validation_error}) on
failure.
}
\seealso{
\code{\link{litport_client}}, \code{\link{get_proxies}},
\code{\link{pick_best}}

\url{https://litport.net/free-proxy}

\url{https://litport.net/docs/free-proxy-api}
}
