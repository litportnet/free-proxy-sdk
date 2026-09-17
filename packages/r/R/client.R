# Client construction, transport, and error helpers for litportFreeProxy.

.litport_default_api_url <- "https://litport.net/api/free-proxy/snapshot?checkedWithinMin=1440"

# Build a condition object for one of the litport_* error classes below.
.litport_error <- function(subclass, message, ...) {
  structure(
    class = c(subclass, "litport_error", "error", "condition"),
    list(message = message, call = NULL, ...)
  )
}

litport_client <- function(api_url = NULL, timeout = 10, transport = NULL, now = NULL) {
  if (!(is.numeric(timeout) && length(timeout) == 1 && !is.na(timeout) &&
        is.finite(timeout) && timeout > 0)) {
    stop(.litport_error("litport_filter_validation_error",
      "timeout must be a positive finite number"))
  }
  if (!is.null(transport) && !is.function(transport)) {
    stop(.litport_error("litport_filter_validation_error",
      "transport must be a function"))
  }
  if (!is.null(now) && !is.function(now)) {
    stop(.litport_error("litport_filter_validation_error",
      "now must be a function"))
  }

  resolved_api_url <- if (is.null(api_url)) .litport_default_api_url else api_url
  resolved_now <- if (is.null(now)) {
    function() {
      instant <- Sys.time()
      attr(instant, "tzone") <- "UTC"
      instant
    }
  } else {
    now
  }

  structure(
    list(
      api_url = resolved_api_url,
      timeout = as.numeric(timeout),
      transport = transport,
      now = resolved_now
    ),
    class = "litport_client"
  )
}

# The snapshot is UTF-8; rawToChar() alone leaves the encoding unmarked, which
# mangles non-ASCII city and organisation names on non-UTF-8 locales.
.litport_utf8 <- function(raw_bytes) {
  text <- rawToChar(raw_bytes)
  Encoding(text) <- "UTF-8"
  text
}

.litport_default_transport <- function(url, timeout) {
  handle <- new_handle(timeout = timeout, connecttimeout = timeout)
  # curl signals every transport failure the same way, so a genuine timeout has
  # to be told apart from DNS, connection, and TLS failures by its message.
  response <- tryCatch(
    curl_fetch_memory(url, handle = handle),
    error = function(e) {
      reason <- conditionMessage(e)
      if (grepl("tim(e|ed)[ ]?out", reason, ignore.case = TRUE)) {
        stop(.litport_error("litport_timeout_error",
          paste0("Snapshot request timed out after ", timeout, "s")))
      }
      stop(.litport_error("litport_transport_error",
        paste0("Snapshot request failed: ", reason)))
    }
  )

  header_text <- rawToChar(response$headers)
  header_lines <- strsplit(header_text, "\r\n")[[1]]
  header_lines <- header_lines[grepl(":", header_lines, fixed = TRUE)]
  header_names <- trimws(sub(":.*$", "", header_lines))
  header_values <- trimws(sub("^[^:]*:", "", header_lines))
  headers <- header_values
  names(headers) <- header_names

  list(
    status = response$status_code,
    headers = headers,
    body = .litport_utf8(response$content)
  )
}

.litport_request <- function(client) {
  if (!is.null(client$transport)) {
    return(client$transport(client$api_url, client$timeout))
  }
  .litport_default_transport(client$api_url, client$timeout)
}
