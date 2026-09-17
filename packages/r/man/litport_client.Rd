\name{litport_client}
\alias{litport_client}
\title{Create a Litport Free Proxy Client}
\usage{
litport_client(api_url = NULL, timeout = 10, transport = NULL, now = NULL)
}
\arguments{
\item{api_url}{Character string giving the snapshot endpoint URL. Defaults
to the public Litport free proxy snapshot API.}

\item{timeout}{Positive, finite number of seconds to wait for the snapshot
request before raising a \code{litport_timeout_error}. Defaults to 10.}

\item{transport}{Optional function with signature \code{function(url,
timeout)} returning \code{list(status, headers, body)}, where
\code{status} is an integer HTTP status code, \code{headers} is a named
character vector, and \code{body} is a character string of JSON. Used to
inject a deterministic transport for testing; when \code{NULL} the client
performs a real HTTP GET request using the curl package.}

\item{now}{Optional zero-argument function returning the current time as a
\code{POSIXct} in UTC. Used to make freshness and envelope validation
deterministic for testing; defaults to the system clock.}
}
\value{
An object of class \code{"litport_client"}: a list holding the validated
\code{api_url}, \code{timeout}, \code{transport}, and \code{now} settings.
Pass it to \code{\link{get_proxies}} or \code{\link{pick_best}}.
}
\details{
The client itself performs no network I/O; it only stores configuration
that is used later by \code{\link{get_proxies}}. Constructing a client
raises a condition of class \code{litport_filter_validation_error} if
\code{timeout} is not a positive, finite number, or if \code{transport} or
\code{now} are supplied but are not functions.
}
\examples{
client <- litport_client()

\dontrun{
proxies <- get_proxies(client, protocol = "socks5", country = "us")
}
}
\seealso{
\code{\link{get_proxies}}, \code{\link{pick_best}}

\url{https://litport.net/free-proxy}

\url{https://litport.net/docs/free-proxy-api}
}
