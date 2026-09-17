# get_proxies() / pick_best() and the row filtering, sorting, and
# data.frame assembly they rely on.

.litport_matches <- function(row, filters) {
  (is.null(filters$protocol) || row$protocol == filters$protocol) &&
    (is.null(filters$country) || (!is.null(row$country) && row$country == filters$country)) &&
    (is.null(filters$anonymity) || row$anonymity == filters$anonymity) &&
    (is.null(filters$https) || (!is.null(row$https) && row$https == filters$https)) &&
    (is.null(filters$max_latency_ms) ||
      (!is.null(row$latency_ms) && row$latency_ms <= filters$max_latency_ms)) &&
    (is.null(filters$min_uptime_7d) ||
      (!is.null(row$uptime_7d) && row$uptime_7d >= filters$min_uptime_7d)) &&
    (is.null(filters$min_checks_7d) || row$checks_7d >= filters$min_checks_7d)
}

# Ascending sort by (has-uptime desc, uptime_7d desc, has-latency desc,
# latency_ms asc, url asc), mirroring the canonical Ruby implementation.
.litport_sort_rows <- function(rows) {
  if (length(rows) == 0) {
    return(rows)
  }
  key_no_uptime <- vapply(rows, function(r) if (is.null(r$uptime_7d)) 1L else 0L, integer(1))
  key_uptime <- vapply(rows, function(r) if (is.null(r$uptime_7d)) 0 else -r$uptime_7d, numeric(1))
  key_no_latency <- vapply(rows, function(r) if (is.null(r$latency_ms)) 1L else 0L, integer(1))
  key_latency <- vapply(rows, function(r) if (is.null(r$latency_ms)) 0L else r$latency_ms, integer(1))
  key_url <- vapply(rows, function(r) r$url, character(1))
  ordering <- order(key_no_uptime, key_uptime, key_no_latency, key_latency, key_url)
  rows[ordering]
}

.litport_empty_proxies_df <- function() {
  data.frame(
    protocol = character(0),
    ip = character(0),
    port = integer(0),
    url = character(0),
    country = character(0),
    region = character(0),
    city = character(0),
    timezone = character(0),
    asn = integer(0),
    asn_org = character(0),
    anonymity = character(0),
    https = logical(0),
    latency_ms = integer(0),
    latency_median_ms = numeric(0),
    uptime_24h = numeric(0),
    uptime_7d = numeric(0),
    checks_7d = integer(0),
    exit_ip = character(0),
    sources_count = integer(0),
    first_seen = as.POSIXct(numeric(0), origin = "1970-01-01", tz = "UTC"),
    last_checked = as.POSIXct(numeric(0), origin = "1970-01-01", tz = "UTC"),
    stringsAsFactors = FALSE
  )
}

# Builds the public data.frame from a list of validated, ordered row lists
# (as produced by .litport_map_row()). Always returns the 21 documented
# columns, in order, with correct types, even when `rows` is empty.
.litport_rows_to_df <- function(rows) {
  if (length(rows) == 0) {
    return(.litport_empty_proxies_df())
  }

  na_chr <- function(x) if (is.null(x)) NA_character_ else x
  na_int <- function(x) if (is.null(x)) NA_integer_ else as.integer(x)
  na_real <- function(x) if (is.null(x)) NA_real_ else as.numeric(x)
  na_lgl <- function(x) if (is.null(x)) NA else x

  df <- data.frame(
    protocol = vapply(rows, function(r) r$protocol, character(1)),
    ip = vapply(rows, function(r) r$ip, character(1)),
    port = vapply(rows, function(r) r$port, integer(1)),
    url = vapply(rows, function(r) r$url, character(1)),
    country = vapply(rows, function(r) na_chr(r$country), character(1)),
    region = vapply(rows, function(r) na_chr(r$region), character(1)),
    city = vapply(rows, function(r) na_chr(r$city), character(1)),
    timezone = vapply(rows, function(r) na_chr(r$timezone), character(1)),
    asn = vapply(rows, function(r) na_int(r$asn), integer(1)),
    asn_org = vapply(rows, function(r) na_chr(r$asn_org), character(1)),
    anonymity = vapply(rows, function(r) r$anonymity, character(1)),
    https = vapply(rows, function(r) na_lgl(r$https), logical(1)),
    latency_ms = vapply(rows, function(r) na_int(r$latency_ms), integer(1)),
    latency_median_ms = vapply(rows, function(r) na_real(r$latency_median_ms), numeric(1)),
    uptime_24h = vapply(rows, function(r) na_real(r$uptime_24h), numeric(1)),
    uptime_7d = vapply(rows, function(r) na_real(r$uptime_7d), numeric(1)),
    checks_7d = vapply(rows, function(r) r$checks_7d, integer(1)),
    exit_ip = vapply(rows, function(r) na_chr(r$exit_ip), character(1)),
    sources_count = vapply(rows, function(r) r$sources_count, integer(1)),
    stringsAsFactors = FALSE
  )

  first_seen_secs <- vapply(rows, function(r) as.numeric(r$first_seen), numeric(1))
  last_checked_secs <- vapply(rows, function(r) as.numeric(r$last_checked), numeric(1))
  df$first_seen <- as.POSIXct(first_seen_secs, origin = "1970-01-01", tz = "UTC")
  df$last_checked <- as.POSIXct(last_checked_secs, origin = "1970-01-01", tz = "UTC")

  df
}

get_proxies <- function(client, ...) {
  if (!inherits(client, "litport_client")) {
    stop(.litport_error("litport_filter_validation_error",
      "client must be a litport_client"))
  }
  filters <- .litport_validate_filters(list(...))

  response <- .litport_request(client)
  if (is.null(response$status) || response$status < 200 || response$status > 299) {
    stop(.litport_error("litport_http_error",
      paste0("Snapshot request failed with HTTP ", response$status),
      status = response$status))
  }

  snapshot <- tryCatch(
    fromJSON(response$body, simplifyVector = FALSE),
    error = function(e) {
      stop(.litport_error("litport_snapshot_validation_error", "Malformed snapshot JSON"))
    }
  )

  proxies_raw <- if (is.list(snapshot)) snapshot[["proxies"]] else NULL
  if (!is.list(snapshot) || is.null(proxies_raw) || !is.list(proxies_raw) ||
      !is.null(names(proxies_raw))) {
    stop(.litport_error("litport_snapshot_validation_error", "Malformed snapshot envelope"))
  }

  count <- snapshot[["count"]]
  truncated <- snapshot[["truncated"]]

  # Mirrors the canonical client: a truncated snapshot is reported before any
  # count/truncated-type structural check, even if that check would also fail.
  if (identical(truncated, TRUE)) {
    stop(.litport_error("litport_snapshot_truncated_error", "Snapshot is truncated"))
  }
  if (!(.litport_is_nonneg_int(count) && as.integer(count) == length(proxies_raw) &&
      (is.null(truncated) || identical(truncated, TRUE) || identical(truncated, FALSE)))) {
    stop(.litport_error("litport_snapshot_validation_error", "Malformed snapshot envelope"))
  }

  now <- client$now()
  .litport_validate_generated_at(snapshot[["generatedAt"]], now)

  rows <- lapply(proxies_raw, .litport_map_row)

  cutoff <- now - filters$checked_within_min * 60
  kept <- Filter(function(row) {
    row$last_checked >= cutoff && row$last_checked <= now + 5 &&
      .litport_matches(row, filters)
  }, rows)

  ordered <- .litport_sort_rows(kept)

  if (!is.null(filters$limit)) {
    limit <- as.integer(filters$limit)
    ordered <- ordered[seq_len(min(length(ordered), limit))]
  }

  .litport_rows_to_df(ordered)
}

pick_best <- function(client, count, ...) {
  if (!.litport_is_nonneg_int(count)) {
    stop(.litport_error("litport_filter_validation_error",
      "count must be a non-negative integer"))
  }
  rows <- get_proxies(client, ...)
  n <- min(nrow(rows), as.integer(count))
  rows[seq_len(n), , drop = FALSE]
}
