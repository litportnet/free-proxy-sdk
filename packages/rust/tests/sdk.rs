use std::{
    collections::{BTreeMap, VecDeque},
    sync::{Arc, Mutex},
    time::Duration,
};

use chrono::{DateTime, Duration as ChronoDuration, Utc};
use litportnet_free_proxy_sdk::{
    Client, Clock, Error, Filters, Protocol, Source, Transport, TransportResponse,
};

const API_SNAPSHOT: &str = include_str!("fixtures/api-snapshot.json");
const GITHUB_PROXIES: &str = include_str!("fixtures/github-proxies.json");

#[derive(Clone)]
struct TestClock(Arc<Mutex<DateTime<Utc>>>);

impl TestClock {
    fn new() -> Self {
        Self(Arc::new(Mutex::new(parse_time("2026-09-10T00:00:00Z"))))
    }

    fn advance(&self, duration: ChronoDuration) {
        *self.0.lock().unwrap() += duration;
    }
}

impl Clock for TestClock {
    fn now(&self) -> DateTime<Utc> {
        *self.0.lock().unwrap()
    }
}

#[derive(Clone)]
struct FixtureTransport {
    responses: Arc<Mutex<VecDeque<TransportResponse>>>,
    requests: Arc<Mutex<Vec<BTreeMap<String, String>>>>,
}

impl FixtureTransport {
    fn new(responses: impl IntoIterator<Item = TransportResponse>) -> Self {
        Self {
            responses: Arc::new(Mutex::new(responses.into_iter().collect())),
            requests: Arc::new(Mutex::new(Vec::new())),
        }
    }

    fn requests(&self) -> Vec<BTreeMap<String, String>> {
        self.requests.lock().unwrap().clone()
    }
}

impl Transport for FixtureTransport {
    fn get(
        &self,
        _url: &str,
        headers: &BTreeMap<String, String>,
        _timeout: Duration,
    ) -> litportnet_free_proxy_sdk::Result<TransportResponse> {
        self.requests.lock().unwrap().push(headers.clone());
        self.responses
            .lock()
            .unwrap()
            .pop_front()
            .ok_or_else(|| Error::Transport("fixture response was not configured".into()))
    }
}

struct TimeoutTransport;

impl Transport for TimeoutTransport {
    fn get(
        &self,
        _url: &str,
        _headers: &BTreeMap<String, String>,
        _timeout: Duration,
    ) -> litportnet_free_proxy_sdk::Result<TransportResponse> {
        Err(Error::Timeout(1))
    }
}

fn parse_time(value: &str) -> DateTime<Utc> {
    DateTime::parse_from_rfc3339(value)
        .unwrap()
        .with_timezone(&Utc)
}

fn response(status: u16, body: impl Into<String>) -> TransportResponse {
    TransportResponse {
        status,
        headers: BTreeMap::from([
            ("ETag".into(), "\"fixture\"".into()),
            ("Cache-Control".into(), "max-age=3600".into()),
        ]),
        body: body.into(),
    }
}

fn fixture_client(source: Source, transport: FixtureTransport, clock: TestClock) -> Client {
    Client::builder()
        .source(source)
        .transport(transport)
        .clock(clock)
        .build()
}

#[test]
fn api_and_github_fixtures_normalize_to_the_same_contract() {
    let clock = TestClock::new();
    let api = fixture_client(
        Source::Api,
        FixtureTransport::new([response(200, API_SNAPSHOT)]),
        clock.clone(),
    );
    let github = fixture_client(
        Source::Github,
        FixtureTransport::new([response(200, GITHUB_PROXIES)]),
        clock,
    );

    let api_rows = api.get_proxies(&Filters::default()).unwrap();
    let github_rows = github.get_proxies(&Filters::default()).unwrap();
    assert_eq!(api_rows, github_rows);
    assert_eq!(api_rows.len(), 2);
    assert_eq!(api_rows[0].proxy_url(), "http://8.8.8.8:8080");
    assert_eq!(api_rows[0].latency_ms, Some(120.0));
    assert_eq!(api_rows[1].uptime_7d, None);
}

#[test]
fn filters_rank_and_return_independent_values() {
    let client = fixture_client(
        Source::Api,
        FixtureTransport::new([response(200, API_SNAPSHOT)]),
        TestClock::new(),
    );
    let filters = Filters::default().protocol(Protocol::Socks5);
    assert_eq!(client.get_proxies(&filters).unwrap().len(), 1);
    assert_eq!(
        client.pick_best(1, &Filters::default()).unwrap()[0].port,
        8080
    );
    assert_eq!(
        client
            .get_proxies(&Filters::default().min_uptime_7d(90))
            .unwrap()
            .len(),
        1
    );
    assert!(matches!(
        client.get_proxies(&Filters::default().country("usa")),
        Err(Error::FilterValidation(_))
    ));
}

#[test]
fn typed_errors_reject_bad_snapshot_responses() {
    let clock = TestClock::new();
    let truncated =
        r#"{"generatedAt":"2026-09-10T00:00:00Z","count":0,"truncated":true,"proxies":[]}"#;
    assert!(matches!(
        fixture_client(
            Source::Api,
            FixtureTransport::new([response(429, "[]")]),
            clock.clone()
        )
        .get_proxies(&Filters::default()),
        Err(Error::Http { status: 429 })
    ));
    assert!(matches!(
        fixture_client(
            Source::Api,
            FixtureTransport::new([response(304, "")]),
            clock.clone()
        )
        .get_proxies(&Filters::default()),
        Err(Error::NotModifiedWithoutCache)
    ));
    assert!(matches!(
        fixture_client(
            Source::Api,
            FixtureTransport::new([response(200, truncated)]),
            clock.clone()
        )
        .get_proxies(&Filters::default()),
        Err(Error::SnapshotTruncated)
    ));
    assert!(matches!(
        fixture_client(
            Source::Api,
            FixtureTransport::new([response(
                200,
                API_SNAPSHOT.replace("00:00:00.000", "23:57:00.000")
            )]),
            clock
        )
        .get_proxies(&Filters::default()),
        Err(Error::SnapshotValidation(_))
    ));
    assert!(matches!(
        Client::builder()
            .transport(TimeoutTransport)
            .clock(TestClock::new())
            .timeout(Duration::from_millis(1))
            .build()
            .get_proxies(&Filters::default()),
        Err(Error::Timeout(1))
    ));
}

#[test]
fn cache_revalidates_with_an_etag_and_rotation_drops_stale_rows() {
    let clock = TestClock::new();
    let mut first = response(200, API_SNAPSHOT);
    first
        .headers
        .insert("Cache-Control".into(), "max-age=0".into());
    let mut second = response(304, "");
    second
        .headers
        .insert("Cache-Control".into(), "max-age=0".into());
    let transport = FixtureTransport::new([first, second]);
    let client = fixture_client(Source::Api, transport.clone(), clock.clone());
    assert_eq!(client.get_proxies(&Filters::default()).unwrap().len(), 2);
    assert_eq!(client.get_proxies(&Filters::default()).unwrap().len(), 2);
    assert_eq!(transport.requests().len(), 2);
    assert_eq!(
        transport.requests()[1].get("If-None-Match"),
        Some(&"\"fixture\"".to_owned())
    );

    let rotation_transport = FixtureTransport::new([response(200, API_SNAPSHOT)]);
    let rotation_client = fixture_client(Source::Api, rotation_transport, clock.clone());
    let mut rotation = rotation_client.rotate(&Filters::default()).unwrap();
    assert_eq!(rotation.next().unwrap().ip, "8.8.8.8");
    clock.advance(ChronoDuration::minutes(21));
    assert_eq!(rotation.next(), None);
}
