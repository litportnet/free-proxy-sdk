//! A synchronous client for Litport's verified free-proxy snapshots.
//!
//! Free proxies are for testing only. Do not send credentials, personal data,
//! cookies, or payment data through them. Browse the list at
//! <https://litport.net/free-proxy>; API documentation is available at
//! <https://litport.net/docs/free-proxy-api>.

use std::{
    cmp::Ordering,
    collections::BTreeMap,
    fmt,
    str::FromStr,
    sync::{Arc, Mutex},
    time::Duration,
};

use chrono::{DateTime, Duration as ChronoDuration, Utc};
use serde_json::{Map, Value};
use thiserror::Error;

/// Default API snapshot URL.
pub const DEFAULT_API_URL: &str =
    "https://litport.net/api/free-proxy/snapshot?checkedWithinMin=1440";
/// Optional GitHub dataset URL.
pub const DEFAULT_GITHUB_URL: &str =
    "https://raw.githubusercontent.com/litportnet/free-proxy-list/live/proxies/all.json";

/// A proxy source.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum Source {
    /// Litport's API snapshot.
    #[default]
    Api,
    /// The optional GitHub dataset.
    Github,
}

/// A proxy protocol accepted by the snapshot contract.
#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub enum Protocol {
    Http,
    Socks4,
    Socks5,
}

impl Protocol {
    fn is_valid(value: &str) -> bool {
        matches!(value, "http" | "socks4" | "socks5")
    }
}

impl fmt::Display for Protocol {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::Http => "http",
            Self::Socks4 => "socks4",
            Self::Socks5 => "socks5",
        })
    }
}

impl FromStr for Protocol {
    type Err = Error;

    fn from_str(value: &str) -> Result<Self> {
        match value {
            "http" => Ok(Self::Http),
            "socks4" => Ok(Self::Socks4),
            "socks5" => Ok(Self::Socks5),
            _ => Err(Error::SnapshotValidation(
                "Snapshot contains an invalid proxy row".into(),
            )),
        }
    }
}

/// A normalized proxy record.
#[derive(Clone, Debug, PartialEq)]
pub struct Proxy {
    pub protocol: Protocol,
    pub ip: String,
    pub port: u16,
    pub url: String,
    pub country: Option<String>,
    pub region: Option<String>,
    pub city: Option<String>,
    pub timezone: Option<String>,
    pub asn: Option<u64>,
    pub asn_org: Option<String>,
    pub anonymity: String,
    pub https: Option<bool>,
    pub latency_ms: Option<f64>,
    pub latency_median_ms: Option<f64>,
    pub uptime_24h: Option<f64>,
    pub uptime_7d: Option<f64>,
    pub checks_7d: u64,
    pub exit_ip: Option<String>,
    pub sources_count: u64,
    pub first_seen: DateTime<Utc>,
    pub last_checked: DateTime<Utc>,
}

impl Proxy {
    /// Formats this record as `protocol://ip:port`.
    pub fn proxy_url(&self) -> String {
        to_proxy_url(self)
    }
}

/// Formats a proxy record as `protocol://ip:port`.
pub fn to_proxy_url(proxy: &Proxy) -> String {
    format!("{}://{}:{}", proxy.protocol, proxy.ip, proxy.port)
}

/// Validated filtering options. `checked_within_min` defaults to 30 when unset.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Filters {
    pub protocol: Option<Protocol>,
    pub country: Option<String>,
    pub anonymity: Option<String>,
    pub https: Option<bool>,
    pub max_latency_ms: Option<u64>,
    pub min_uptime_7d: Option<u64>,
    pub min_checks_7d: Option<u64>,
    pub checked_within_min: Option<u16>,
    pub limit: Option<usize>,
}

impl Filters {
    pub fn protocol(mut self, value: Protocol) -> Self {
        self.protocol = Some(value);
        self
    }

    pub fn country(mut self, value: impl Into<String>) -> Self {
        self.country = Some(value.into());
        self
    }

    pub fn anonymity(mut self, value: impl Into<String>) -> Self {
        self.anonymity = Some(value.into());
        self
    }

    pub fn https(mut self, value: bool) -> Self {
        self.https = Some(value);
        self
    }

    pub fn max_latency_ms(mut self, value: u64) -> Self {
        self.max_latency_ms = Some(value);
        self
    }

    pub fn min_uptime_7d(mut self, value: u64) -> Self {
        self.min_uptime_7d = Some(value);
        self
    }

    pub fn min_checks_7d(mut self, value: u64) -> Self {
        self.min_checks_7d = Some(value);
        self
    }

    pub fn checked_within_min(mut self, value: u16) -> Self {
        self.checked_within_min = Some(value);
        self
    }

    pub fn limit(mut self, value: usize) -> Self {
        self.limit = Some(value);
        self
    }

    fn validate(&self) -> Result<ValidatedFilters> {
        let country = self.country.as_deref().map(str::to_ascii_lowercase);
        if country.as_deref().is_some_and(|value| {
            value.len() != 2 || !value.bytes().all(|byte| byte.is_ascii_lowercase())
        }) {
            return Err(Error::FilterValidation(
                "country must be a two-letter code".into(),
            ));
        }
        if self.anonymity.as_deref().is_some_and(|value| {
            !matches!(value, "transparent" | "anonymous" | "elite" | "unknown")
        }) {
            return Err(Error::FilterValidation("Invalid anonymity value".into()));
        }
        let checked_within_min = self.checked_within_min.unwrap_or(30);
        if !(1..=1440).contains(&checked_within_min) {
            return Err(Error::FilterValidation(
                "checked_within_min must be an integer from 1 to 1440".into(),
            ));
        }
        Ok(ValidatedFilters {
            protocol: self.protocol,
            country,
            anonymity: self.anonymity.clone(),
            https: self.https,
            max_latency_ms: self.max_latency_ms,
            min_uptime_7d: self.min_uptime_7d,
            min_checks_7d: self.min_checks_7d,
            checked_within_min,
            limit: self.limit,
        })
    }
}

#[derive(Clone)]
struct ValidatedFilters {
    protocol: Option<Protocol>,
    country: Option<String>,
    anonymity: Option<String>,
    https: Option<bool>,
    max_latency_ms: Option<u64>,
    min_uptime_7d: Option<u64>,
    min_checks_7d: Option<u64>,
    checked_within_min: u16,
    limit: Option<usize>,
}

/// Snapshot-client errors.
#[derive(Debug, Error)]
pub enum Error {
    #[error("Snapshot request timed out after {0}ms")]
    Timeout(u64),
    #[error("Snapshot request failed with HTTP {status}")]
    Http { status: u16 },
    #[error("Received 304 without a cached snapshot")]
    NotModifiedWithoutCache,
    #[error("{0}")]
    SnapshotValidation(String),
    #[error("Snapshot is truncated")]
    SnapshotTruncated,
    #[error("{0}")]
    FilterValidation(String),
    #[error("Snapshot request failed: {0}")]
    Transport(String),
}

/// Convenient result alias for this crate.
pub type Result<T> = std::result::Result<T, Error>;

/// The response returned by a [`Transport`]. Header names are case-insensitive.
#[derive(Clone, Debug, Default)]
pub struct TransportResponse {
    pub status: u16,
    pub headers: BTreeMap<String, String>,
    pub body: String,
}

/// Synchronous HTTP adapter used by [`Client`].
///
/// Provide a custom implementation in tests to avoid live network requests.
pub trait Transport: Send + Sync {
    fn get(
        &self,
        url: &str,
        headers: &BTreeMap<String, String>,
        timeout: Duration,
    ) -> Result<TransportResponse>;
}

/// The default HTTPS transport, implemented with `reqwest` and rustls.
#[derive(Clone, Debug, Default)]
pub struct ReqwestTransport;

impl Transport for ReqwestTransport {
    fn get(
        &self,
        url: &str,
        headers: &BTreeMap<String, String>,
        timeout: Duration,
    ) -> Result<TransportResponse> {
        let client = reqwest::blocking::Client::builder()
            .timeout(timeout)
            .build()
            .map_err(|error| Error::Transport(error.to_string()))?;
        let mut request = client.get(url);
        for (name, value) in headers {
            request = request.header(name, value);
        }
        let response = request.send().map_err(|error| {
            if error.is_timeout() {
                Error::Timeout(duration_millis(timeout))
            } else {
                Error::Transport(error.to_string())
            }
        })?;
        let status = response.status().as_u16();
        let headers = response
            .headers()
            .iter()
            .filter_map(|(name, value)| {
                value
                    .to_str()
                    .ok()
                    .map(|value| (name.to_string(), value.to_owned()))
            })
            .collect();
        let body = response.text().map_err(|error| {
            if error.is_timeout() {
                Error::Timeout(duration_millis(timeout))
            } else {
                Error::Transport(error.to_string())
            }
        })?;
        Ok(TransportResponse {
            status,
            headers,
            body,
        })
    }
}

/// Source of time for freshness checks and cache expiry.
pub trait Clock: Send + Sync {
    fn now(&self) -> DateTime<Utc>;
}

/// The normal UTC system clock.
#[derive(Clone, Debug, Default)]
pub struct SystemClock;

impl Clock for SystemClock {
    fn now(&self) -> DateTime<Utc> {
        Utc::now()
    }
}

struct Cache {
    rows: Vec<Proxy>,
    etag: Option<String>,
    generated_at: Option<DateTime<Utc>>,
    expires_at: DateTime<Utc>,
}

/// Builder for a [`Client`].
pub struct ClientBuilder {
    source: Source,
    api_url: String,
    github_url: String,
    transport: Arc<dyn Transport>,
    clock: Arc<dyn Clock>,
    timeout: Duration,
}

impl Default for ClientBuilder {
    fn default() -> Self {
        Self {
            source: Source::Api,
            api_url: DEFAULT_API_URL.into(),
            github_url: DEFAULT_GITHUB_URL.into(),
            transport: Arc::new(ReqwestTransport),
            clock: Arc::new(SystemClock),
            timeout: Duration::from_secs(10),
        }
    }
}

impl ClientBuilder {
    pub fn source(mut self, value: Source) -> Self {
        self.source = value;
        self
    }

    pub fn api_url(mut self, value: impl Into<String>) -> Self {
        self.api_url = value.into();
        self
    }

    pub fn github_url(mut self, value: impl Into<String>) -> Self {
        self.github_url = value.into();
        self
    }

    pub fn transport(mut self, value: impl Transport + 'static) -> Self {
        self.transport = Arc::new(value);
        self
    }

    pub fn clock(mut self, value: impl Clock + 'static) -> Self {
        self.clock = Arc::new(value);
        self
    }

    pub fn timeout(mut self, value: Duration) -> Self {
        self.timeout = value;
        self
    }

    pub fn build(self) -> Client {
        Client {
            source: self.source,
            api_url: self.api_url,
            github_url: self.github_url,
            transport: self.transport,
            clock: self.clock,
            timeout: self.timeout,
            cache: Mutex::new(None),
        }
    }
}

/// Synchronous Litport free-proxy client.
pub struct Client {
    source: Source,
    api_url: String,
    github_url: String,
    transport: Arc<dyn Transport>,
    clock: Arc<dyn Clock>,
    timeout: Duration,
    cache: Mutex<Option<Cache>>,
}

impl Default for Client {
    fn default() -> Self {
        Self::new()
    }
}

impl Client {
    /// Creates an API client with the default HTTPS transport.
    pub fn new() -> Self {
        Self::builder().build()
    }

    pub fn builder() -> ClientBuilder {
        ClientBuilder::default()
    }

    /// Gets normalized, fresh proxy rows sorted by uptime, latency, then URL.
    pub fn get_proxies(&self, filters: &Filters) -> Result<Vec<Proxy>> {
        self.get_proxies_checked(filters.validate()?)
    }

    /// Alias for [`Client::get_proxies`].
    pub fn filter(&self, filters: &Filters) -> Result<Vec<Proxy>> {
        self.get_proxies(filters)
    }

    /// Gets the first `n` ranked proxy rows.
    pub fn pick_best(&self, n: usize, filters: &Filters) -> Result<Vec<Proxy>> {
        Ok(self
            .get_proxies_checked(filters.validate()?)?
            .into_iter()
            .take(n)
            .collect())
    }

    /// Creates a rotation over the currently matching rows.
    ///
    /// The rotation retains its initial members but skips records that become
    /// stale before a subsequent call to [`Iterator::next`].
    pub fn rotate(&self, filters: &Filters) -> Result<Rotation> {
        let filters = filters.validate()?;
        let rows = self.get_proxies_checked(filters.clone())?;
        Ok(Rotation {
            rows,
            index: 0,
            filters,
            clock: Arc::clone(&self.clock),
        })
    }

    fn get_proxies_checked(&self, filters: ValidatedFilters) -> Result<Vec<Proxy>> {
        let rows = self.rows()?;
        let now = self.clock.now();
        let cutoff = now - ChronoDuration::minutes(i64::from(filters.checked_within_min));
        let mut matching = rows
            .into_iter()
            .filter(|row| {
                row.last_checked >= cutoff && row.last_checked <= now + ChronoDuration::seconds(5)
            })
            .filter(|row| filters.protocol.is_none_or(|value| row.protocol == value))
            .filter(|row| {
                filters
                    .country
                    .as_deref()
                    .is_none_or(|value| row.country.as_deref() == Some(value))
            })
            .filter(|row| {
                filters
                    .anonymity
                    .as_deref()
                    .is_none_or(|value| row.anonymity == value)
            })
            .filter(|row| filters.https.is_none_or(|value| row.https == Some(value)))
            .filter(|row| {
                filters.max_latency_ms.is_none_or(|value| {
                    row.latency_ms
                        .is_some_and(|latency| latency <= value as f64)
                })
            })
            .filter(|row| {
                filters
                    .min_uptime_7d
                    .is_none_or(|value| row.uptime_7d.is_some_and(|uptime| uptime >= value as f64))
            })
            .filter(|row| {
                filters
                    .min_checks_7d
                    .is_none_or(|value| row.checks_7d >= value)
            })
            .collect::<Vec<_>>();
        matching.sort_by(sort_proxies);
        if let Some(limit) = filters.limit {
            matching.truncate(limit);
        }
        Ok(matching)
    }

    fn rows(&self) -> Result<Vec<Proxy>> {
        let now = self.clock.now();
        let mut cache = self.cache.lock().expect("client cache mutex poisoned");
        if let Some(cached) = cache.as_ref().filter(|cached| now < cached.expires_at) {
            self.validate_generated_at(cached.generated_at, now)?;
            return Ok(cached.rows.clone());
        }
        let mut headers = BTreeMap::new();
        if let Some(etag) = cache.as_ref().and_then(|cached| cached.etag.as_ref()) {
            headers.insert("If-None-Match".into(), etag.clone());
        }
        let response = self.transport.get(
            if self.source == Source::Api {
                &self.api_url
            } else {
                &self.github_url
            },
            &headers,
            self.timeout,
        )?;
        if response.status == 304 {
            let cached = cache.as_mut().ok_or(Error::NotModifiedWithoutCache)?;
            self.validate_generated_at(cached.generated_at, now)?;
            cached.expires_at = now + ChronoDuration::seconds(cache_seconds(&response.headers));
            return Ok(cached.rows.clone());
        }
        if !(200..300).contains(&response.status) {
            return Err(Error::Http {
                status: response.status,
            });
        }
        let body: Value = serde_json::from_str(&response.body)
            .map_err(|_| Error::SnapshotValidation("Malformed snapshot JSON".into()))?;
        let (rows, generated_at) = self.parse_snapshot(body, now)?;
        *cache = Some(Cache {
            rows: rows.clone(),
            etag: header(&response.headers, "etag"),
            generated_at,
            expires_at: now + ChronoDuration::seconds(cache_seconds(&response.headers)),
        });
        Ok(rows)
    }

    fn parse_snapshot(
        &self,
        body: Value,
        now: DateTime<Utc>,
    ) -> Result<(Vec<Proxy>, Option<DateTime<Utc>>)> {
        if self.source == Source::Github {
            let rows = body
                .as_array()
                .ok_or_else(|| Error::SnapshotValidation("Malformed GitHub proxy list".into()))?;
            return Ok((
                rows.iter()
                    .map(|row| map_row(row, Source::Github))
                    .collect::<Result<_>>()?,
                None,
            ));
        }
        let snapshot = body
            .as_object()
            .ok_or_else(|| Error::SnapshotValidation("Malformed snapshot envelope".into()))?;
        if snapshot.get("truncated").and_then(Value::as_bool) == Some(true) {
            return Err(Error::SnapshotTruncated);
        }
        let proxies = snapshot
            .get("proxies")
            .and_then(Value::as_array)
            .ok_or_else(|| Error::SnapshotValidation("Malformed snapshot envelope".into()))?;
        if snapshot.get("count").and_then(Value::as_u64) != Some(proxies.len() as u64)
            || snapshot
                .get("truncated")
                .is_some_and(|value| !value.is_boolean())
        {
            return Err(Error::SnapshotValidation(
                "Malformed snapshot envelope".into(),
            ));
        }
        let generated_at = parse_time(snapshot.get("generatedAt"))?;
        self.validate_generated_at(Some(generated_at), now)?;
        Ok((
            proxies
                .iter()
                .map(|row| map_row(row, Source::Api))
                .collect::<Result<_>>()?,
            Some(generated_at),
        ))
    }

    fn validate_generated_at(
        &self,
        value: Option<DateTime<Utc>>,
        now: DateTime<Utc>,
    ) -> Result<()> {
        if self.source != Source::Api {
            return Ok(());
        }
        let generated_at = value.ok_or_else(|| {
            Error::SnapshotValidation("Snapshot generatedAt is outside the accepted window".into())
        })?;
        if generated_at > now + ChronoDuration::seconds(5)
            || generated_at < now - ChronoDuration::minutes(2)
        {
            return Err(Error::SnapshotValidation(
                "Snapshot generatedAt is outside the accepted window".into(),
            ));
        }
        Ok(())
    }
}

/// Iterator returned by [`Client::rotate`].
pub struct Rotation {
    rows: Vec<Proxy>,
    index: usize,
    filters: ValidatedFilters,
    clock: Arc<dyn Clock>,
}

impl Iterator for Rotation {
    type Item = Proxy;

    fn next(&mut self) -> Option<Self::Item> {
        if self.rows.is_empty() {
            return None;
        }
        let now = self.clock.now();
        let cutoff = now - ChronoDuration::minutes(i64::from(self.filters.checked_within_min));
        for _ in 0..self.rows.len() {
            let row = self.rows[self.index % self.rows.len()].clone();
            self.index += 1;
            if row.last_checked >= cutoff && row.last_checked <= now + ChronoDuration::seconds(5) {
                return Some(row);
            }
        }
        None
    }
}

fn map_row(row: &Value, source: Source) -> Result<Proxy> {
    let row = row.as_object().ok_or_else(|| {
        Error::SnapshotValidation("Snapshot contains an invalid proxy row".into())
    })?;
    let key = |api, github| if source == Source::Api { api } else { github };
    let protocol_text = required_string(row, key("protocol", "protocol"))?;
    if !Protocol::is_valid(protocol_text) {
        return invalid_row();
    }
    let protocol = Protocol::from_str(protocol_text)?;
    let ip = required_string(row, key("host", "ip"))?.to_owned();
    let port = required_u64(row, key("port", "port"))?;
    let port = u16::try_from(port)
        .map_err(|_| Error::SnapshotValidation("Snapshot contains an invalid proxy row".into()))?;
    if port == 0 || !public_ipv4(&ip) {
        return invalid_row();
    }
    let country =
        nullable_string(row, key("geoCountry", "country"))?.map(|value| value.to_ascii_lowercase());
    if country.as_deref().is_some_and(|value| {
        value.len() != 2 || !value.bytes().all(|byte| byte.is_ascii_lowercase())
    }) {
        return Err(Error::SnapshotValidation("Invalid country".into()));
    }
    let asn = nullable_asn(row, key("asn", "asn"))?;
    let anonymity = required_string(row, key("anonymity", "anonymity"))?.to_owned();
    if !matches!(
        anonymity.as_str(),
        "transparent" | "anonymous" | "elite" | "unknown"
    ) {
        return invalid_row();
    }
    let https = nullable_bool(row, key("https", "https"))?;
    let mut latency_ms = nullable_number(row, key("responseTimeMs", "latency_ms"))?;
    if source == Source::Api {
        latency_ms = latency_ms.map(|value| (value + 0.5).floor());
    }
    let checks_7d = required_u64(row, key("checks7d", "checks_7d"))?;
    let sources_count = required_u64(row, key("sourcesCount", "sources_count"))?;
    let first_seen = parse_time(row.get(key("createdAt", "first_seen")))?;
    let last_checked = parse_time(row.get(key("pingAt", "last_checked")))?;
    let uptime_7d = nullable_number(row, key("uptime7d", "uptime_7d"))?;
    Ok(Proxy {
        protocol,
        ip: ip.clone(),
        port,
        url: format!("{protocol}://{ip}:{port}"),
        country,
        region: nullable_string(row, key("geoRegion", "region"))?,
        city: nullable_string(row, key("geoCity", "city"))?,
        timezone: nullable_string(row, key("geoTimezone", "timezone"))?,
        asn,
        asn_org: nullable_string(row, key("asnOrgName", "asn_org"))?,
        anonymity,
        https,
        latency_ms,
        latency_median_ms: nullable_number(row, key("responseTimeMedianMs", "latency_median_ms"))?,
        uptime_24h: nullable_number(row, key("uptime24h", "uptime_24h"))?,
        uptime_7d: if checks_7d < 50 { None } else { uptime_7d },
        checks_7d,
        exit_ip: nullable_string(row, key("externalIp", "exit_ip"))?,
        sources_count,
        first_seen,
        last_checked,
    })
}

fn required_string<'a>(row: &'a Map<String, Value>, key: &str) -> Result<&'a str> {
    row.get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| Error::SnapshotValidation("Snapshot contains an invalid proxy row".into()))
}

fn required_u64(row: &Map<String, Value>, key: &str) -> Result<u64> {
    row.get(key)
        .and_then(Value::as_u64)
        .ok_or_else(|| Error::SnapshotValidation("Snapshot contains an invalid proxy row".into()))
}

fn nullable_string(row: &Map<String, Value>, key: &str) -> Result<Option<String>> {
    match row.get(key) {
        Some(Value::Null) => Ok(None),
        Some(Value::String(value)) => Ok(Some(value.clone())),
        _ => Err(Error::SnapshotValidation(format!("Invalid {key}"))),
    }
}

fn nullable_bool(row: &Map<String, Value>, key: &str) -> Result<Option<bool>> {
    match row.get(key) {
        Some(Value::Null) => Ok(None),
        Some(Value::Bool(value)) => Ok(Some(*value)),
        _ => Err(Error::SnapshotValidation("Invalid https value".into())),
    }
}

fn nullable_number(row: &Map<String, Value>, key: &str) -> Result<Option<f64>> {
    match row.get(key) {
        Some(Value::Null) => Ok(None),
        Some(value) => value
            .as_f64()
            .filter(|value| value.is_finite())
            .map(Some)
            .ok_or_else(|| Error::SnapshotValidation(format!("Invalid {key}"))),
        None => Err(Error::SnapshotValidation(format!("Invalid {key}"))),
    }
}

fn nullable_asn(row: &Map<String, Value>, key: &str) -> Result<Option<u64>> {
    match row.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Number(value)) => value
            .as_u64()
            .map(Some)
            .ok_or_else(|| Error::SnapshotValidation("Invalid ASN".into())),
        Some(Value::String(value)) => value
            .strip_prefix("AS")
            .or_else(|| value.strip_prefix("as"))
            .unwrap_or(value)
            .parse::<u64>()
            .map(Some)
            .map_err(|_| Error::SnapshotValidation("Invalid ASN".into())),
        _ => Err(Error::SnapshotValidation("Invalid ASN".into())),
    }
}

fn parse_time(value: Option<&Value>) -> Result<DateTime<Utc>> {
    let value = value.and_then(Value::as_str).ok_or_else(|| {
        Error::SnapshotValidation("Snapshot contains an invalid proxy row".into())
    })?;
    if value.len() < 20 {
        return invalid_row();
    }
    DateTime::parse_from_rfc3339(value)
        .map(|value| value.with_timezone(&Utc))
        .map_err(|_| Error::SnapshotValidation("Snapshot contains an invalid proxy row".into()))
}

fn invalid_row<T>() -> Result<T> {
    Err(Error::SnapshotValidation(
        "Snapshot contains an invalid proxy row".into(),
    ))
}

fn public_ipv4(value: &str) -> bool {
    let parts = value
        .split('.')
        .map(str::parse::<u8>)
        .collect::<std::result::Result<Vec<_>, _>>();
    let Ok(parts) = parts else { return false };
    if parts.len() != 4 {
        return false;
    }
    let address = u32::from_be_bytes([parts[0], parts[1], parts[2], parts[3]]);
    const RANGES: &[(u32, u8)] = &[
        (0x0000_0000, 8),
        (0x0a00_0000, 8),
        (0x6440_0000, 10),
        (0x7f00_0000, 8),
        (0xa9fe_0000, 16),
        (0xac10_0000, 12),
        (0xc000_0000, 24),
        (0xc000_0200, 24),
        (0xc0a8_0000, 16),
        (0xc612_0000, 15),
        (0xc633_6400, 24),
        (0xcb00_7100, 24),
        (0xe000_0000, 4),
        (0xf000_0000, 4),
    ];
    !RANGES
        .iter()
        .any(|(network, prefix)| address >> (32 - prefix) == network >> (32 - prefix))
}

fn sort_proxies(left: &Proxy, right: &Proxy) -> Ordering {
    left.uptime_7d
        .is_none()
        .cmp(&right.uptime_7d.is_none())
        .then_with(|| {
            right
                .uptime_7d
                .unwrap_or(0.0)
                .total_cmp(&left.uptime_7d.unwrap_or(0.0))
        })
        .then_with(|| left.latency_ms.is_none().cmp(&right.latency_ms.is_none()))
        .then_with(|| {
            left.latency_ms
                .unwrap_or(0.0)
                .total_cmp(&right.latency_ms.unwrap_or(0.0))
        })
        .then_with(|| left.url.cmp(&right.url))
}

fn header(headers: &BTreeMap<String, String>, name: &str) -> Option<String> {
    headers
        .iter()
        .find(|(key, _)| key.eq_ignore_ascii_case(name))
        .map(|(_, value)| value.clone())
}

fn cache_seconds(headers: &BTreeMap<String, String>) -> i64 {
    let max_age = header(headers, "cache-control")
        .as_deref()
        .and_then(|value| {
            value.split(',').find_map(|directive| {
                let (name, value) = directive.trim().split_once('=')?;
                name.trim()
                    .eq_ignore_ascii_case("max-age")
                    .then(|| value.trim().parse::<i64>().ok())
                    .flatten()
            })
        })
        .unwrap_or(60);
    max_age.clamp(0, 60)
}

fn duration_millis(duration: Duration) -> u64 {
    duration.as_millis().try_into().unwrap_or(u64::MAX)
}
