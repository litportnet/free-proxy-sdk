\name{get_proxies}
\alias{get_proxies}
\title{Fetch and Filter Litport Free Proxies}
\usage{
get_proxies(client, ...)
}
\arguments{
\item{client}{A \code{"litport_client"} object created by
\code{\link{litport_client}}.}

\item{...}{Named filters. Supported names are \code{protocol} (one of
\code{"http"}, \code{"socks4"}, \code{"socks5"}), \code{country} (a
two-letter code), \code{anonymity} (one of \code{"transparent"},
\code{"anonymous"}, \code{"elite"}, \code{"unknown"}), \code{https}
(logical), \code{max_latency_ms}, \code{min_uptime_7d},
\code{min_checks_7d}, and \code{limit} (each a non-negative integer), and
\code{checked_within_min} (an integer from 1 to 1440, default 30).
Unrecognized names raise \code{litport_filter_validation_error}.}
}
\value{
A \code{data.frame} with one row per matching proxy and the columns
\code{protocol}, \code{ip}, \code{port}, \code{url}, \code{country},
\code{region}, \code{city}, \code{timezone}, \code{asn}, \code{asn_org},
\code{anonymity}, \code{https}, \code{latency_ms},
\code{latency_median_ms}, \code{uptime_24h}, \code{uptime_7d},
\code{checks_7d}, \code{exit_ip}, \code{sources_count}, \code{first_seen},
and \code{last_checked} (the last two as \code{POSIXct} in UTC). When no
proxies match, a zero-row \code{data.frame} with the same columns and
column types is returned rather than \code{NULL}.
}
\details{
The snapshot envelope and every proxy row are validated before filtering.
Invalid envelopes raise \code{litport_snapshot_validation_error}; a
\code{truncated} snapshot raises \code{litport_snapshot_truncated_error};
an HTTP status outside 200-299 raises \code{litport_http_error} (carrying
a \code{status} element); a transport timeout raises
\code{litport_timeout_error}; any other transport failure, such as a
name-resolution or TLS error, raises \code{litport_transport_error}.
Proxy \code{host} values are validated as
public IPv4 addresses, rejecting private and other reserved ranges. A
row's \code{uptime_7d} is forced to \code{NA} whenever it has fewer than
50 checks in the last 7 days. Only rows whose \code{last_checked}
timestamp falls within \code{checked_within_min} minutes of the current
time (and no more than 5 seconds in the future) are kept. Results are
sorted with non-missing \code{uptime_7d} first (descending), then
non-missing \code{latency_ms} first (ascending), then \code{url}
(ascending), before \code{limit} is applied.
}
\examples{
client <- litport_client()

\dontrun{
proxies <- get_proxies(client, protocol = "socks5", country = "us",
  limit = 5)
proxies$url
}
}
\seealso{
\code{\link{litport_client}}, \code{\link{pick_best}}

\url{https://litport.net/free-proxy}

\url{https://litport.net/docs/free-proxy-api}
}
