NOW <- as.POSIXct("2026-09-10 00:00:00", tz = "UTC")

fixture_list <- function() {
  jsonlite::fromJSON(test_path("fixtures", "api_snapshot.json"), simplifyVector = FALSE)
}

fixture_body <- function(snapshot = fixture_list()) {
  as.character(jsonlite::toJSON(snapshot, auto_unbox = TRUE, null = "null"))
}

make_client <- function(body = fixture_body(), status = 200L, timeout = 10) {
  litport_client(
    timeout = timeout,
    now = function() NOW,
    transport = function(url, timeout) list(status = status, headers = character(0), body = body)
  )
}

test_that("litport_client validates timeout and defaults api_url", {
  client <- litport_client()
  expect_s3_class(client, "litport_client")
  expect_match(client$api_url, "^https://litport\\.net/api/free-proxy/snapshot")

  expect_error(litport_client(timeout = -1), class = "litport_filter_validation_error")
  expect_error(litport_client(timeout = Inf), class = "litport_filter_validation_error")
  expect_error(litport_client(timeout = 0), class = "litport_filter_validation_error")
})

test_that("get_proxies normalizes fields, sorts, and nulls low-sample uptime", {
  rows <- get_proxies(make_client())

  expect_equal(nrow(rows), 5)
  expect_equal(
    c("protocol", "ip", "port", "url", "country", "region", "city", "timezone",
      "asn", "asn_org", "anonymity", "https", "latency_ms", "latency_median_ms",
      "uptime_24h", "uptime_7d", "checks_7d", "exit_ip", "sources_count",
      "first_seen", "last_checked"),
    names(rows)
  )

  # Best row first: highest uptime_7d (record with 99.9% uptime).
  expect_equal(rows$url[1], "http://45.33.32.156:3128")
  expect_equal(rows$latency_ms[1], 50L)
  expect_equal(rows$asn[1], 63949L)
  expect_s3_class(rows$first_seen, "POSIXct")
  expect_s3_class(rows$last_checked, "POSIXct")

  # The record with fewer than 50 checks in 7 days sorts last (NA uptime).
  expect_equal(rows$ip[nrow(rows)], "1.1.1.1")
  expect_true(is.na(rows$uptime_7d[nrow(rows)]))
})

test_that("get_proxies applies filters", {
  expect_equal(nrow(get_proxies(make_client(), protocol = "socks5")), 1)
  expect_equal(nrow(get_proxies(make_client(), country = "US")), 2)
  expect_equal(nrow(get_proxies(make_client(), country = "us")), 2)
  expect_equal(nrow(get_proxies(make_client(), min_uptime_7d = 90)), 2)
  expect_equal(nrow(get_proxies(make_client(), min_checks_7d = 50)), 4)
  expect_equal(nrow(get_proxies(make_client(), checked_within_min = 1440)), 6)
})

test_that("get_proxies returns a correctly typed zero-row data.frame", {
  rows <- get_proxies(make_client(), limit = 0)
  expect_equal(nrow(rows), 0)
  expect_true(is.integer(rows$port))
  expect_true(is.numeric(rows$uptime_7d))
  expect_s3_class(rows$first_seen, "POSIXct")
})

test_that("pick_best returns at most count rows, best first", {
  best <- pick_best(make_client(), 1)
  expect_equal(nrow(best), 1)
  expect_equal(best$url[1], "http://45.33.32.156:3128")

  expect_error(pick_best(make_client(), -1), class = "litport_filter_validation_error")
})

test_that("HTTP status outside 200-299 raises litport_http_error with a status", {
  err <- tryCatch(
    get_proxies(make_client(body = "{}", status = 429L)),
    litport_http_error = function(e) e
  )
  expect_s3_class(err, "litport_http_error")
  expect_equal(err$status, 429L)
})

test_that("a truncated snapshot raises litport_snapshot_truncated_error", {
  body <- fixture_body(list(
    generatedAt = "2026-09-10T00:00:00Z", count = 0, truncated = TRUE, proxies = list()
  ))
  expect_error(get_proxies(make_client(body = body)), class = "litport_snapshot_truncated_error")
})

test_that("generatedAt outside the accepted window is rejected", {
  stale <- fixture_body(list(generatedAt = "2026-09-09T23:57:00Z", count = 0, proxies = list()))
  expect_error(get_proxies(make_client(body = stale)), class = "litport_snapshot_validation_error")

  future <- fixture_body(list(generatedAt = "2026-09-10T00:00:06Z", count = 0, proxies = list()))
  expect_error(get_proxies(make_client(body = future)), class = "litport_snapshot_validation_error")
})

test_that("a mismatched count is rejected", {
  invalid <- fixture_list()
  invalid$count <- 99
  expect_error(get_proxies(make_client(body = fixture_body(invalid))),
    class = "litport_snapshot_validation_error")
})

test_that("malformed JSON raises litport_snapshot_validation_error", {
  expect_error(get_proxies(make_client(body = "{broken")),
    class = "litport_snapshot_validation_error")
})

test_that("invalid proxy row fields are rejected", {
  bad_field_cases <- list(
    list(field = "host", value = "127.0.0.1"),
    list(field = "port", value = "8080"),
    list(field = "asn", value = TRUE),
    list(field = "geoCountry", value = 123),
    list(field = "responseTimeMs", value = "fast"),
    list(field = "pingAt", value = "2026-09-10T00:00:00"),
    list(field = "createdAt", value = "2026-02-30T00:00:00Z")
  )
  for (case in bad_field_cases) {
    invalid <- fixture_list()
    invalid$proxies[[1]][[case$field]] <- case$value
    expect_error(
      get_proxies(make_client(body = fixture_body(invalid))),
      class = "litport_snapshot_validation_error"
    )
  }

  # A missing (as opposed to malformed) required field is invalid too.
  missing_host <- fixture_list()
  missing_host$proxies[[1]]$host <- NULL
  expect_error(
    get_proxies(make_client(body = fixture_body(missing_host))),
    class = "litport_snapshot_validation_error"
  )
})

test_that("a proxy that falls outside the freshness window is dropped", {
  invalid <- fixture_list()
  invalid$proxies[[1]]$pingAt <- "2026-09-09T23:29:59Z"
  rows <- get_proxies(make_client(body = fixture_body(invalid)))
  expect_equal(nrow(rows), 4)
})

test_that("filter validation rejects bad or unknown filters", {
  bad_filters <- list(
    list(https = "yes"),
    list(protocol = FALSE),
    list(checked_within_min = FALSE),
    list(limit = -1),
    list(unknown = 1)
  )
  for (filters in bad_filters) {
    expect_error(
      do.call(get_proxies, c(list(make_client()), filters)),
      class = "litport_filter_validation_error"
    )
  }
})

test_that("the transport receives the configured timeout and can report a timeout", {
  received <- NULL
  timeout_client <- litport_client(
    timeout = 1.5,
    now = function() NOW,
    transport = function(url, timeout) {
      received <<- timeout
      stop(structure(
        class = c("litport_timeout_error", "litport_error", "error", "condition"),
        list(message = "Snapshot request timed out after 1.5s", call = NULL)
      ))
    }
  )
  expect_error(get_proxies(timeout_client), class = "litport_timeout_error")
  expect_equal(received, 1.5)
})
