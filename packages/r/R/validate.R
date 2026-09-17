# Constants and validation helpers for litportFreeProxy.

.litport_protocols <- c("http", "socks4", "socks5")
.litport_anonymity <- c("transparent", "anonymous", "elite", "unknown")

.litport_blocked_ranges <- list(
  list(network = "0.0.0.0", prefix = 8),
  list(network = "10.0.0.0", prefix = 8),
  list(network = "100.64.0.0", prefix = 10),
  list(network = "127.0.0.0", prefix = 8),
  list(network = "169.254.0.0", prefix = 16),
  list(network = "172.16.0.0", prefix = 12),
  list(network = "192.0.0.0", prefix = 24),
  list(network = "192.0.2.0", prefix = 24),
  list(network = "192.168.0.0", prefix = 16),
  list(network = "198.18.0.0", prefix = 15),
  list(network = "198.51.100.0", prefix = 24),
  list(network = "203.0.113.0", prefix = 24),
  list(network = "224.0.0.0", prefix = 4),
  list(network = "240.0.0.0", prefix = 4)
)

.litport_allowed_filters <- c(
  "protocol", "country", "anonymity", "https", "max_latency_ms",
  "min_uptime_7d", "min_checks_7d", "limit", "checked_within_min"
)

# R's base round() rounds halves to even; the canonical client rounds
# response times the way most languages do (halves away from zero). Latency
# is always non-negative, so a simple floor(x + 0.5) is sufficient here.
.litport_round_half_up <- function(x) {
  floor(x + 0.5)
}

.litport_is_whole_number <- function(x) {
  is.numeric(x) && length(x) == 1 && !is.na(x) && is.finite(x) && x == floor(x)
}

.litport_is_nonneg_int <- function(x) {
  .litport_is_whole_number(x) && x >= 0
}

.litport_ipv4_to_int <- function(ip) {
  parts <- strsplit(ip, ".", fixed = TRUE)[[1]]
  if (length(parts) != 4 || !all(grepl("^[0-9]{1,3}$", parts))) {
    return(NA_real_)
  }
  nums <- as.numeric(parts)
  if (any(is.na(nums)) || any(nums < 0) || any(nums > 255)) {
    return(NA_real_)
  }
  nums[1] * 2^24 + nums[2] * 2^16 + nums[3] * 2^8 + nums[4]
}

.litport_is_public_ipv4 <- function(value) {
  if (!is.character(value) || length(value) != 1 || is.na(value)) {
    return(FALSE)
  }
  ip_int <- .litport_ipv4_to_int(value)
  if (is.na(ip_int)) {
    return(FALSE)
  }
  for (range in .litport_blocked_ranges) {
    network_int <- .litport_ipv4_to_int(range$network)
    block_size <- 2^(32 - range$prefix)
    if (ip_int >= network_int && ip_int < network_int + block_size) {
      return(FALSE)
    }
  }
  TRUE
}

.litport_leap_year <- function(year) {
  (year %% 4 == 0 && year %% 100 != 0) || year %% 400 == 0
}

.litport_valid_date <- function(year, month, day) {
  if (is.na(year) || is.na(month) || is.na(day)) {
    return(FALSE)
  }
  if (month < 1 || month > 12) {
    return(FALSE)
  }
  days_in_month <- c(31, if (.litport_leap_year(year)) 29 else 28, 31, 30, 31,
    30, 31, 31, 30, 31, 30, 31)
  day >= 1 && day <= days_in_month[month]
}

# Parses a strict RFC 3339 / ISO 8601 timestamp (as produced by the Litport
# API) into a POSIXct in UTC. Returns NULL when the string does not match
# the expected shape or names an invalid calendar date.
.litport_parse_time <- function(value) {
  if (!is.character(value) || length(value) != 1 || is.na(value)) {
    return(NULL)
  }
  pattern <- paste0(
    "^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})",
    "(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"
  )
  match <- regmatches(value, regexec(pattern, value))[[1]]
  if (length(match) == 0) {
    return(NULL)
  }

  year <- as.integer(match[2])
  month <- as.integer(match[3])
  day <- as.integer(match[4])
  hour <- as.integer(match[5])
  minute <- as.integer(match[6])
  second <- as.integer(match[7])
  frac <- match[8]
  offset <- match[9]

  if (!.litport_valid_date(year, month, day)) {
    return(NULL)
  }
  if (hour > 23 || minute > 59 || second > 59) {
    return(NULL)
  }

  frac_seconds <- if (nzchar(frac)) as.numeric(frac) else 0
  offset_seconds <- 0
  if (offset != "Z") {
    sign <- if (substr(offset, 1, 1) == "-") -1 else 1
    off_hour <- as.integer(substr(offset, 2, 3))
    off_minute <- as.integer(substr(offset, 5, 6))
    offset_seconds <- sign * (off_hour * 3600 + off_minute * 60)
  }

  base <- ISOdate(year, month, day, hour, minute, second, tz = "UTC")
  result <- base + frac_seconds - offset_seconds
  attr(result, "tzone") <- "UTC"
  result
}

.litport_validate_generated_at <- function(value, now) {
  parsed <- .litport_parse_time(value)
  if (is.null(parsed) || parsed > now + 5 || parsed < now - 120) {
    stop(.litport_error("litport_snapshot_validation_error",
      "Snapshot generatedAt is outside the accepted window"))
  }
}

# Parses the "asn" field, which the API represents either as a bare
# non-negative integer or as a string like "AS15169". Returns a list with
# ok = TRUE/FALSE and, when ok, the integer value (or NULL when absent).
.litport_parse_asn <- function(asn) {
  if (is.null(asn)) {
    return(list(ok = TRUE, value = NULL))
  }
  if (is.character(asn) && length(asn) == 1 && !is.na(asn)) {
    match <- regmatches(asn, regexec("^AS([0-9]+)$", asn))[[1]]
    if (length(match) == 2) {
      return(list(ok = TRUE, value = as.integer(match[2])))
    }
    return(list(ok = FALSE, value = NULL))
  }
  if (.litport_is_nonneg_int(asn)) {
    return(list(ok = TRUE, value = as.integer(asn)))
  }
  list(ok = FALSE, value = NULL)
}

.litport_is_nullable_string <- function(value) {
  is.null(value) || (is.character(value) && length(value) == 1 && !is.na(value))
}

.litport_is_nullable_number <- function(value) {
  is.null(value) || (is.numeric(value) && length(value) == 1 && !is.na(value) &&
    is.finite(value))
}

.litport_is_nullable_bool <- function(value) {
  is.null(value) || (is.logical(value) && length(value) == 1 && !is.na(value))
}

.litport_is_two_letter_code <- function(value) {
  is.null(value) || (is.character(value) && length(value) == 1 && !is.na(value) &&
    grepl("^[A-Za-z]{2}$", value))
}

# Validates and normalizes one snapshot proxy row into a plain list, or
# raises litport_snapshot_validation_error when the row is malformed.
.litport_map_row <- function(row) {
  invalid_row <- function(message) {
    stop(.litport_error("litport_snapshot_validation_error", message))
  }

  if (!is.list(row)) {
    invalid_row("Snapshot contains an invalid proxy row")
  }

  protocol <- row[["protocol"]]
  ip <- row[["host"]]
  port <- row[["port"]]
  anonymity <- row[["anonymity"]]

  valid_protocol <- is.character(protocol) && length(protocol) == 1 &&
    !is.na(protocol) && protocol %in% .litport_protocols
  valid_ip <- .litport_is_public_ipv4(ip)
  valid_port <- .litport_is_whole_number(port) && port >= 1 && port <= 65535
  valid_anonymity <- is.character(anonymity) && length(anonymity) == 1 &&
    !is.na(anonymity) && anonymity %in% .litport_anonymity

  if (!(valid_protocol && valid_ip && valid_port && valid_anonymity)) {
    invalid_row("Snapshot contains an invalid proxy row")
  }

  country <- row[["geoCountry"]]
  if (!.litport_is_two_letter_code(country)) {
    invalid_row("Invalid country")
  }

  asn_result <- .litport_parse_asn(row[["asn"]])
  if (!asn_result$ok) {
    invalid_row("Invalid ASN")
  }

  for (field in c("geoRegion", "geoCity", "geoTimezone", "asnOrgName", "externalIp")) {
    if (!.litport_is_nullable_string(row[[field]])) {
      invalid_row("Invalid nullable string")
    }
  }

  if (!.litport_is_nullable_bool(row[["https"]])) {
    invalid_row("Invalid https value")
  }

  for (field in c("responseTimeMs", "responseTimeMedianMs", "uptime24h", "uptime7d")) {
    if (!.litport_is_nullable_number(row[[field]])) {
      invalid_row("Invalid nullable number")
    }
  }

  checks_7d <- row[["checks7d"]]
  sources_count <- row[["sourcesCount"]]
  if (!(.litport_is_nonneg_int(checks_7d) && .litport_is_nonneg_int(sources_count))) {
    invalid_row("Invalid count")
  }

  first_seen <- .litport_parse_time(row[["createdAt"]])
  last_checked <- .litport_parse_time(row[["pingAt"]])
  if (is.null(first_seen) || is.null(last_checked)) {
    invalid_row("Invalid timestamp")
  }

  checks_7d_int <- as.integer(checks_7d)
  uptime_7d_raw <- row[["uptime7d"]]
  uptime_7d <- if (checks_7d_int < 50 || is.null(uptime_7d_raw)) {
    NULL
  } else {
    as.numeric(uptime_7d_raw)
  }

  port_int <- as.integer(port)
  list(
    protocol = protocol,
    ip = ip,
    port = port_int,
    url = paste0(protocol, "://", ip, ":", port_int),
    country = if (is.null(country)) NULL else tolower(country),
    region = row[["geoRegion"]],
    city = row[["geoCity"]],
    timezone = row[["geoTimezone"]],
    asn = asn_result$value,
    asn_org = row[["asnOrgName"]],
    anonymity = anonymity,
    https = row[["https"]],
    latency_ms = if (is.null(row[["responseTimeMs"]])) NULL else as.integer(.litport_round_half_up(row[["responseTimeMs"]])),
    latency_median_ms = if (is.null(row[["responseTimeMedianMs"]])) NULL else as.numeric(row[["responseTimeMedianMs"]]),
    uptime_24h = if (is.null(row[["uptime24h"]])) NULL else as.numeric(row[["uptime24h"]]),
    uptime_7d = uptime_7d,
    checks_7d = checks_7d_int,
    exit_ip = row[["externalIp"]],
    sources_count = as.integer(sources_count),
    first_seen = first_seen,
    last_checked = last_checked
  )
}

# Validates and normalizes the named filters passed as `...` to get_proxies()
# and pick_best(). Unknown names, or values of the wrong type or out of
# range, raise litport_filter_validation_error.
.litport_validate_filters <- function(filters) {
  invalid_filter <- function(message) {
    stop(.litport_error("litport_filter_validation_error", message))
  }

  names_given <- names(filters)
  if (is.null(names_given)) {
    names_given <- character(0)
  }
  unknown <- setdiff(names_given, .litport_allowed_filters)
  if (length(unknown) > 0) {
    invalid_filter(paste0("Unknown filter: ", unknown[1]))
  }

  protocol <- filters[["protocol"]]
  if (!is.null(protocol) && !(is.character(protocol) && length(protocol) == 1 &&
      !is.na(protocol) && protocol %in% .litport_protocols)) {
    invalid_filter("protocol must be http, socks4, or socks5")
  }

  country <- filters[["country"]]
  if (!is.null(country) && !.litport_is_two_letter_code(country)) {
    invalid_filter("country must be a two-letter code")
  }

  anonymity <- filters[["anonymity"]]
  if (!is.null(anonymity) && !(is.character(anonymity) && length(anonymity) == 1 &&
      !is.na(anonymity) && anonymity %in% .litport_anonymity)) {
    invalid_filter("Invalid anonymity value")
  }

  https <- filters[["https"]]
  if (!is.null(https) && !.litport_is_nullable_bool(https)) {
    invalid_filter("https must be boolean")
  }

  for (name in c("max_latency_ms", "min_uptime_7d", "min_checks_7d", "limit")) {
    value <- filters[[name]]
    if (!is.null(value) && !.litport_is_nonneg_int(value)) {
      invalid_filter(paste0(name, " must be a non-negative integer"))
    }
  }

  checked_within_min <- filters[["checked_within_min"]]
  if (is.null(checked_within_min)) {
    checked_within_min <- 30
  }
  if (!(.litport_is_whole_number(checked_within_min) && checked_within_min >= 1 &&
      checked_within_min <= 1440)) {
    invalid_filter("checked_within_min must be from 1 to 1440")
  }

  list(
    protocol = protocol,
    country = if (is.null(country)) NULL else tolower(country),
    anonymity = anonymity,
    https = https,
    max_latency_ms = filters[["max_latency_ms"]],
    min_uptime_7d = filters[["min_uptime_7d"]],
    min_checks_7d = filters[["min_checks_7d"]],
    limit = filters[["limit"]],
    checked_within_min = as.integer(checked_within_min)
  )
}
