package freeproxy

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

const defaultTimeout = 10 * time.Second

type cachedSnapshot struct {
	rows        []Proxy
	etag        string
	generatedAt string
	expiresAt   time.Time
}

// Client retrieves and filters free-proxy snapshots.
type Client struct {
	source    Source
	apiURL    string
	githubURL string
	http      *http.Client
	now       func() time.Time
	timeout   time.Duration

	mu    sync.Mutex
	cache *cachedSnapshot
}

// NewClient creates a Client. It does not make a network request.
func NewClient(options ClientOptions) (*Client, error) {
	source := options.Source
	if source == "" {
		source = SourceAPI
	}
	if source != SourceAPI && source != SourceGitHub {
		return nil, &FilterValidationError{Message: "source must be api or github"}
	}
	timeout := options.Timeout
	if timeout == 0 {
		timeout = defaultTimeout
	}
	if timeout < 0 {
		return nil, &FilterValidationError{Message: "timeout must be positive"}
	}
	now := options.Now
	if now == nil {
		now = time.Now
	}
	client := options.HTTPClient
	if client == nil {
		client = &http.Client{Transport: options.Transport}
	}
	return &Client{
		source: source, apiURL: defaultString(options.APIURL, DefaultAPIURL), githubURL: defaultString(options.GitHubURL, DefaultGitHubURL),
		http: client, now: now, timeout: timeout,
	}, nil
}

func defaultString(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}

func validateFilters(filters Filters) (Filters, error) {
	if filters.Protocol != "" && filters.Protocol != "http" && filters.Protocol != "socks4" && filters.Protocol != "socks5" {
		return Filters{}, &FilterValidationError{Message: "protocol must be http, socks4, or socks5"}
	}
	if filters.Country != "" && !countryCode(filters.Country) {
		return Filters{}, &FilterValidationError{Message: "country must be a two-letter code"}
	}
	if filters.Anonymity != "" && filters.Anonymity != "transparent" && filters.Anonymity != "anonymous" && filters.Anonymity != "elite" && filters.Anonymity != "unknown" {
		return Filters{}, &FilterValidationError{Message: "invalid anonymity value"}
	}
	for _, check := range []struct {
		name  string
		value *int
	}{{"maxLatencyMS", filters.MaxLatencyMS}, {"minUptime7d", filters.MinUptime7d}, {"minChecks7d", filters.MinChecks7d}, {"limit", filters.Limit}} {
		if check.value != nil && *check.value < 0 {
			return Filters{}, &FilterValidationError{Message: check.name + " must be a non-negative integer"}
		}
	}
	if filters.CheckedWithinMin == nil {
		filters.CheckedWithinMin = Int(30)
	}
	if *filters.CheckedWithinMin < 1 || *filters.CheckedWithinMin > 1440 {
		return Filters{}, &FilterValidationError{Message: "checkedWithinMin must be an integer from 1 to 1440"}
	}
	filters.Country = strings.ToLower(filters.Country)
	return filters, nil
}

// GetProxies retrieves the current snapshot and returns matching proxies in deterministic rank order.
func (c *Client) GetProxies(ctx context.Context, filters Filters) ([]Proxy, error) {
	filters, err := validateFilters(filters)
	if err != nil {
		return nil, err
	}
	rows, err := c.rows(ctx)
	if err != nil {
		return nil, err
	}
	now := c.now()
	cutoff := now.Add(-time.Duration(*filters.CheckedWithinMin) * time.Minute)
	matched := make([]Proxy, 0, len(rows))
	for _, row := range rows {
		checkedAt, _ := parseTimestamp(row.LastChecked)
		if checkedAt.Before(cutoff) || checkedAt.After(now.Add(5*time.Second)) {
			continue
		}
		if filters.Protocol != "" && row.Protocol != filters.Protocol || filters.Country != "" && valueOrEmpty(row.Country) != filters.Country || filters.Anonymity != "" && row.Anonymity != filters.Anonymity || filters.HTTPS != nil && (row.HTTPS == nil || *row.HTTPS != *filters.HTTPS) || filters.MaxLatencyMS != nil && (row.LatencyMS == nil || *row.LatencyMS > float64(*filters.MaxLatencyMS)) || filters.MinUptime7d != nil && (row.Uptime7d == nil || *row.Uptime7d < float64(*filters.MinUptime7d)) || filters.MinChecks7d != nil && row.Checks7d < *filters.MinChecks7d {
			continue
		}
		matched = append(matched, row)
	}
	sortProxies(matched)
	if filters.Limit != nil && len(matched) > *filters.Limit {
		matched = matched[:*filters.Limit]
	}
	return cloneProxies(matched), nil
}

// PickBest returns at most n top-ranked matching proxies.
func (c *Client) PickBest(ctx context.Context, n int, filters Filters) ([]Proxy, error) {
	if n < 0 {
		return nil, &FilterValidationError{Message: "n must be a non-negative integer"}
	}
	rows, err := c.GetProxies(ctx, filters)
	if err != nil || len(rows) <= n {
		return rows, err
	}
	return rows[:n], nil
}

// Rotator cycles through the initial matching records and stops returning records that expire.
type Rotator struct {
	client  *Client
	filters Filters
	rows    []Proxy
	index   int
}

// Rotate creates a Rotator from the current matching records.
func (c *Client) Rotate(ctx context.Context, filters Filters) (*Rotator, error) {
	filters, err := validateFilters(filters)
	if err != nil {
		return nil, err
	}
	rows, err := c.GetProxies(ctx, filters)
	if err != nil {
		return nil, err
	}
	return &Rotator{client: c, filters: filters, rows: rows}, nil
}

// Next returns the next still-fresh proxy. ok is false when no records remain.
func (r *Rotator) Next() (proxy Proxy, ok bool) {
	if r == nil || len(r.rows) == 0 {
		return Proxy{}, false
	}
	now := r.client.now()
	cutoff := now.Add(-time.Duration(*r.filters.CheckedWithinMin) * time.Minute)
	for tries := 0; tries < len(r.rows); tries++ {
		row := r.rows[r.index%len(r.rows)]
		r.index++
		checkedAt, _ := parseTimestamp(row.LastChecked)
		if !checkedAt.Before(cutoff) && !checkedAt.After(now.Add(5*time.Second)) {
			return cloneProxy(row), true
		}
	}
	return Proxy{}, false
}

func (c *Client) rows(ctx context.Context) ([]Proxy, error) {
	now := c.now()
	c.mu.Lock()
	if c.cache != nil && now.Before(c.cache.expiresAt) {
		cache := *c.cache
		c.mu.Unlock()
		if err := c.validateGeneratedAt(cache.generatedAt, now); err != nil {
			return nil, err
		}
		return cloneProxies(cache.rows), nil
	}
	var etag string
	if c.cache != nil {
		etag = c.cache.etag
	}
	c.mu.Unlock()

	response, err := c.request(ctx, etag)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusNotModified {
		c.mu.Lock()
		defer c.mu.Unlock()
		if c.cache == nil {
			return nil, &NotModifiedWithoutCacheError{}
		}
		if err := c.validateGeneratedAt(c.cache.generatedAt, now); err != nil {
			return nil, err
		}
		c.cache.expiresAt = now.Add(cacheDuration(response.Header))
		return cloneProxies(c.cache.rows), nil
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return nil, &HTTPError{StatusCode: response.StatusCode}
	}
	rows, generatedAt, err := c.decodeSnapshot(response, now)
	if err != nil {
		return nil, err
	}
	cache := &cachedSnapshot{rows: rows, etag: response.Header.Get("ETag"), generatedAt: generatedAt, expiresAt: now.Add(cacheDuration(response.Header))}
	c.mu.Lock()
	c.cache = cache
	c.mu.Unlock()
	return cloneProxies(rows), nil
}

func (c *Client) request(ctx context.Context, etag string) (*http.Response, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	ctx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()
	url := c.apiURL
	if c.source == SourceGitHub {
		url = c.githubURL
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, &RequestError{Err: err}
	}
	if etag != "" {
		req.Header.Set("If-None-Match", etag)
	}
	response, err := c.http.Do(req)
	if err != nil {
		if errors.Is(ctx.Err(), context.DeadlineExceeded) || errors.Is(err, context.DeadlineExceeded) {
			return nil, &TimeoutError{Timeout: c.timeout}
		}
		return nil, &RequestError{Err: err}
	}
	return response, nil
}

func (c *Client) decodeSnapshot(response *http.Response, now time.Time) ([]Proxy, string, error) {
	decoder := json.NewDecoder(response.Body)
	if c.source == SourceAPI {
		var envelope struct {
			GeneratedAt *string           `json:"generatedAt"`
			Count       *int              `json:"count"`
			Truncated   *bool             `json:"truncated"`
			Proxies     []json.RawMessage `json:"proxies"`
		}
		if err := decoder.Decode(&envelope); err != nil {
			return nil, "", &SnapshotValidationError{Message: "malformed snapshot JSON"}
		}
		if err := ensureEOF(decoder); err != nil {
			return nil, "", &SnapshotValidationError{Message: "malformed snapshot JSON"}
		}
		if envelope.Truncated != nil && *envelope.Truncated {
			return nil, "", &SnapshotTruncatedError{}
		}
		if envelope.GeneratedAt == nil || envelope.Count == nil || envelope.Proxies == nil || envelope.Truncated != nil && *envelope.Truncated {
			return nil, "", &SnapshotValidationError{Message: "malformed snapshot envelope"}
		}
		if *envelope.Count != len(envelope.Proxies) {
			return nil, "", &SnapshotValidationError{Message: "malformed snapshot envelope"}
		}
		if err := c.validateGeneratedAt(*envelope.GeneratedAt, now); err != nil {
			return nil, "", err
		}
		rows := make([]Proxy, 0, len(envelope.Proxies))
		for _, raw := range envelope.Proxies {
			row, err := mapRow(raw, SourceAPI)
			if err != nil {
				return nil, "", err
			}
			rows = append(rows, row)
		}
		return rows, *envelope.GeneratedAt, nil
	}
	var rawRows []json.RawMessage
	if err := decoder.Decode(&rawRows); err != nil || rawRows == nil {
		return nil, "", &SnapshotValidationError{Message: "malformed GitHub proxy list"}
	}
	if err := ensureEOF(decoder); err != nil {
		return nil, "", &SnapshotValidationError{Message: "malformed GitHub proxy list"}
	}
	rows := make([]Proxy, 0, len(rawRows))
	for _, raw := range rawRows {
		row, err := mapRow(raw, SourceGitHub)
		if err != nil {
			return nil, "", err
		}
		rows = append(rows, row)
	}
	return rows, "", nil
}

func ensureEOF(decoder *json.Decoder) error {
	var extra any
	err := decoder.Decode(&extra)
	if err == io.EOF {
		return nil
	}
	if err == nil {
		return fmt.Errorf("unexpected JSON value")
	}
	return err
}

func (c *Client) validateGeneratedAt(value string, now time.Time) error {
	if c.source != SourceAPI {
		return nil
	}
	generatedAt, err := parseTimestamp(value)
	if err != nil || generatedAt.After(now.Add(5*time.Second)) || generatedAt.Before(now.Add(-2*time.Minute)) {
		return &SnapshotValidationError{Message: "snapshot generatedAt is outside the accepted window"}
	}
	return nil
}

func cacheDuration(headers http.Header) time.Duration {
	for _, part := range strings.Split(headers.Get("Cache-Control"), ",") {
		parts := strings.SplitN(strings.TrimSpace(part), "=", 2)
		if len(parts) == 2 && strings.EqualFold(parts[0], "max-age") {
			if seconds, err := strconv.Atoi(parts[1]); err == nil && seconds >= 0 {
				if seconds > 60 {
					seconds = 60
				}
				return time.Duration(seconds) * time.Second
			}
		}
	}
	return time.Minute
}

func valueOrEmpty(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

func cloneProxy(proxy Proxy) Proxy {
	copyString := func(value *string) *string {
		if value == nil {
			return nil
		}
		copy := *value
		return &copy
	}
	copyInt := func(value *int) *int {
		if value == nil {
			return nil
		}
		copy := *value
		return &copy
	}
	copyBool := func(value *bool) *bool {
		if value == nil {
			return nil
		}
		copy := *value
		return &copy
	}
	copyFloat := func(value *float64) *float64 {
		if value == nil {
			return nil
		}
		copy := *value
		return &copy
	}
	proxy.Country = copyString(proxy.Country)
	proxy.Region = copyString(proxy.Region)
	proxy.City = copyString(proxy.City)
	proxy.Timezone = copyString(proxy.Timezone)
	proxy.ASN = copyInt(proxy.ASN)
	proxy.ASNOrg = copyString(proxy.ASNOrg)
	proxy.HTTPS = copyBool(proxy.HTTPS)
	proxy.LatencyMS = copyFloat(proxy.LatencyMS)
	proxy.LatencyMedianMS = copyFloat(proxy.LatencyMedianMS)
	proxy.Uptime24h = copyFloat(proxy.Uptime24h)
	proxy.Uptime7d = copyFloat(proxy.Uptime7d)
	proxy.ExitIP = copyString(proxy.ExitIP)
	return proxy
}

func cloneProxies(rows []Proxy) []Proxy {
	cloned := make([]Proxy, len(rows))
	for index, row := range rows {
		cloned[index] = cloneProxy(row)
	}
	return cloned
}

func parseTimestamp(value string) (time.Time, error) {
	if len(value) < 20 {
		return time.Time{}, fmt.Errorf("invalid timestamp")
	}
	parsed, err := time.Parse(time.RFC3339Nano, value)
	if err != nil {
		return time.Time{}, err
	}
	return parsed.UTC(), nil
}

func canonicalTimestamp(value string) (string, error) {
	parsed, err := parseTimestamp(value)
	if err != nil {
		return "", err
	}
	return parsed.Format("2006-01-02T15:04:05.000Z"), nil
}

func sortProxies(rows []Proxy) {
	for i := 1; i < len(rows); i++ {
		for j := i; j > 0 && lessProxy(rows[j], rows[j-1]); j-- {
			rows[j], rows[j-1] = rows[j-1], rows[j]
		}
	}
}

func lessProxy(a, b Proxy) bool {
	if (a.Uptime7d == nil) != (b.Uptime7d == nil) {
		return a.Uptime7d != nil
	}
	if a.Uptime7d != nil && *a.Uptime7d != *b.Uptime7d {
		return *a.Uptime7d > *b.Uptime7d
	}
	if (a.LatencyMS == nil) != (b.LatencyMS == nil) {
		return a.LatencyMS != nil
	}
	if a.LatencyMS != nil && *a.LatencyMS != *b.LatencyMS {
		return *a.LatencyMS < *b.LatencyMS
	}
	return a.URL < b.URL
}

func countryCode(value string) bool {
	if len(value) != 2 {
		return false
	}
	for _, char := range value {
		if !(char >= 'a' && char <= 'z' || char >= 'A' && char <= 'Z') {
			return false
		}
	}
	return true
}

func publicIPv4(value string) bool {
	parts := strings.Split(value, ".")
	if len(parts) != 4 {
		return false
	}
	var number uint32
	for _, part := range parts {
		if part == "" {
			return false
		}
		for _, char := range part {
			if char < '0' || char > '9' {
				return false
			}
		}
		byteValue, err := strconv.ParseUint(part, 10, 8)
		if err != nil {
			return false
		}
		number = number<<8 | uint32(byteValue)
	}
	for _, block := range []struct {
		network uint32
		prefix  uint
	}{
		{0x00000000, 8}, {0x0a000000, 8}, {0x64400000, 10}, {0x7f000000, 8}, {0xa9fe0000, 16}, {0xac100000, 12}, {0xc0000000, 24}, {0xc0000200, 24}, {0xc0a80000, 16}, {0xc6120000, 15}, {0xc6336400, 24}, {0xcb007100, 24}, {0xe0000000, 4}, {0xf0000000, 4},
	} {
		mask := ^uint32(0) << (32 - block.prefix)
		if number&mask == block.network&mask {
			return false
		}
	}
	return true
}

func mapRow(raw json.RawMessage, source Source) (Proxy, error) {
	var values map[string]json.RawMessage
	if err := json.Unmarshal(raw, &values); err != nil || values == nil {
		return Proxy{}, &SnapshotValidationError{Message: "snapshot contains an invalid proxy row"}
	}
	field := func(api, github string) json.RawMessage {
		if source == SourceAPI {
			return values[api]
		}
		return values[github]
	}
	protocol, ok := requiredString(field("protocol", "protocol"))
	if !ok {
		return invalidRow()
	}
	ip, ok := requiredString(field("host", "ip"))
	if !ok {
		return invalidRow()
	}
	port, ok := requiredInt(field("port", "port"))
	if !ok {
		return invalidRow()
	}
	firstSeen, ok := requiredString(field("createdAt", "first_seen"))
	if !ok {
		return invalidRow()
	}
	lastChecked, ok := requiredString(field("pingAt", "last_checked"))
	if !ok {
		return invalidRow()
	}
	firstSeen, err := canonicalTimestamp(firstSeen)
	if err != nil {
		return invalidRow()
	}
	lastChecked, err = canonicalTimestamp(lastChecked)
	if err != nil {
		return invalidRow()
	}
	country, ok := nullableString(field("geoCountry", "country"))
	if !ok {
		return invalidRow()
	}
	region, ok := nullableString(field("geoRegion", "region"))
	if !ok {
		return invalidRow()
	}
	city, ok := nullableString(field("geoCity", "city"))
	if !ok {
		return invalidRow()
	}
	timezone, ok := nullableString(field("geoTimezone", "timezone"))
	if !ok {
		return invalidRow()
	}
	asnOrg, ok := nullableString(field("asnOrgName", "asn_org"))
	if !ok {
		return invalidRow()
	}
	exitIP, ok := nullableString(field("externalIp", "exit_ip"))
	if !ok {
		return invalidRow()
	}
	anonymity, ok := requiredString(field("anonymity", "anonymity"))
	if !ok {
		return invalidRow()
	}
	https, ok := nullableBool(field("https", "https"))
	if !ok {
		return invalidRow()
	}
	latency, ok := nullableNumber(field("responseTimeMs", "latency_ms"))
	if !ok {
		return invalidRow()
	}
	latencyMedian, ok := nullableNumber(field("responseTimeMedianMs", "latency_median_ms"))
	if !ok {
		return invalidRow()
	}
	uptime24, ok := nullableNumber(field("uptime24h", "uptime_24h"))
	if !ok {
		return invalidRow()
	}
	uptime7, ok := nullableNumber(field("uptime7d", "uptime_7d"))
	if !ok {
		return invalidRow()
	}
	checks, ok := requiredInt(field("checks7d", "checks_7d"))
	if !ok {
		return invalidRow()
	}
	sources, ok := requiredInt(field("sourcesCount", "sources_count"))
	if !ok {
		return invalidRow()
	}
	asn, ok := nullableASN(field("asn", "asn"))
	if !ok {
		return invalidRow()
	}
	if source == SourceAPI && latency != nil {
		rounded := math.Floor(*latency + 0.5)
		latency = &rounded
	}
	if country != nil {
		lower := strings.ToLower(*country)
		country = &lower
	}
	proxy := Proxy{Protocol: protocol, IP: ip, Port: port, URL: fmt.Sprintf("%s://%s:%d", protocol, ip, port), Country: country, Region: region, City: city, Timezone: timezone, ASN: asn, ASNOrg: asnOrg, Anonymity: anonymity, HTTPS: https, LatencyMS: latency, LatencyMedianMS: latencyMedian, Uptime24h: uptime24, Uptime7d: uptime7, Checks7d: checks, ExitIP: exitIP, SourcesCount: sources, FirstSeen: firstSeen, LastChecked: lastChecked}
	if proxy.Protocol != "http" && proxy.Protocol != "socks4" && proxy.Protocol != "socks5" || !publicIPv4(proxy.IP) || proxy.Port < 1 || proxy.Port > 65535 || proxy.Anonymity != "transparent" && proxy.Anonymity != "anonymous" && proxy.Anonymity != "elite" && proxy.Anonymity != "unknown" || proxy.Country != nil && !countryCode(*proxy.Country) || proxy.ASN != nil && *proxy.ASN < 0 || proxy.Checks7d < 0 || proxy.SourcesCount < 0 {
		return invalidRow()
	}
	if proxy.Checks7d < 50 {
		proxy.Uptime7d = nil
	}
	return proxy, nil
}

func invalidRow() (Proxy, error) {
	return Proxy{}, &SnapshotValidationError{Message: "snapshot contains an invalid proxy row"}
}

func requiredString(raw json.RawMessage) (string, bool) {
	if isNullOrMissing(raw) {
		return "", false
	}
	var value string
	return value, json.Unmarshal(raw, &value) == nil
}

func nullableString(raw json.RawMessage) (*string, bool) {
	if isNull(raw) {
		return nil, true
	}
	if raw == nil {
		return nil, false
	}
	var value string
	if json.Unmarshal(raw, &value) != nil {
		return nil, false
	}
	return &value, true
}

func nullableBool(raw json.RawMessage) (*bool, bool) {
	if isNull(raw) {
		return nil, true
	}
	if raw == nil {
		return nil, false
	}
	var value bool
	if json.Unmarshal(raw, &value) != nil {
		return nil, false
	}
	return &value, true
}

func nullableNumber(raw json.RawMessage) (*float64, bool) {
	if isNull(raw) {
		return nil, true
	}
	if raw == nil {
		return nil, false
	}
	var value float64
	if json.Unmarshal(raw, &value) != nil || math.IsNaN(value) || math.IsInf(value, 0) {
		return nil, false
	}
	return &value, true
}

func requiredInt(raw json.RawMessage) (int, bool) {
	if isNullOrMissing(raw) {
		return 0, false
	}
	var value int
	return value, json.Unmarshal(raw, &value) == nil
}

func nullableASN(raw json.RawMessage) (*int, bool) {
	if isNull(raw) {
		return nil, true
	}
	if raw == nil {
		return nil, false
	}
	var number json.Number
	if json.Unmarshal(raw, &number) == nil {
		value, err := strconv.Atoi(number.String())
		if err == nil {
			return &value, true
		}
	}
	var text string
	if json.Unmarshal(raw, &text) != nil {
		return nil, false
	}
	text = strings.TrimPrefix(text, "AS")
	value, err := strconv.Atoi(text)
	if err != nil {
		return nil, false
	}
	return &value, true
}

func isNull(raw json.RawMessage) bool          { return len(raw) == 4 && string(raw) == "null" }
func isNullOrMissing(raw json.RawMessage) bool { return raw == nil || isNull(raw) }
