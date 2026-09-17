\name{pick_best}
\alias{pick_best}
\title{Fetch the Best Litport Free Proxies}
\usage{
pick_best(client, count, ...)
}
\arguments{
\item{client}{A \code{"litport_client"} object created by
\code{\link{litport_client}}.}

\item{count}{Non-negative integer giving the maximum number of rows to
return.}

\item{...}{Named filters passed through to \code{\link{get_proxies}}; see
its documentation for the supported names.}
}
\value{
A \code{data.frame} with the same columns as \code{\link{get_proxies}},
containing at most \code{count} rows taken from the front of the sorted,
filtered result. When no proxies match, a zero-row \code{data.frame} with
the same columns and column types is returned rather than \code{NULL}.
}
\details{
\code{pick_best} is equivalent to calling \code{\link{get_proxies}} with
the same filters and then taking the first \code{count} rows, since
\code{\link{get_proxies}} already returns results sorted best-first. It
raises \code{litport_filter_validation_error} if \code{count} is not a
non-negative integer.
}
\examples{
client <- litport_client()

\dontrun{
best <- pick_best(client, 5, protocol = "http")
best$url
}
}
\seealso{
\code{\link{litport_client}}, \code{\link{get_proxies}}

\url{https://litport.net/free-proxy}

\url{https://litport.net/docs/free-proxy-api}
}
