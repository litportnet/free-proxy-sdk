// Package freeproxy provides a dependency-free client for Litport free-proxy snapshots.
package freeproxy

import (
	"fmt"
	"net/http"
	"time"
)

const (
	// DefaultAPIURL is the live Litport API snapshot endpoint.
	DefaultAPIURL = "https://litport.net/api/free-proxy/snapshot?checkedWithinMin=1440"
	// DefaultGitHubURL is the optional GitHub snapshot endpoint.
	DefaultGitHubURL = "https://raw.githubusercontent.com/litportnet/free-proxy-list/live/proxies/all.json"
)

// Source selects the snapshot provider.
type Source string

const (
	SourceAPI    Source = "api"
	SourceGitHub Source = "github"
)

// Proxy is a normalized proxy record. Its JSON keys match the SDK fixture contract.
type Proxy struct {
	Protocol        string   `json:"protocol"`
	IP              string   `json:"ip"`
	Port            int      `json:"port"`
	URL             string   `json:"url"`
	Country         *string  `json:"country"`
	Region          *string  `json:"region"`
	City            *string  `json:"city"`
	Timezone        *string  `json:"timezone"`
	ASN             *int     `json:"asn"`
	ASNOrg          *string  `json:"asnOrg"`
	Anonymity       string   `json:"anonymity"`
	HTTPS           *bool    `json:"https"`
	LatencyMS       *float64 `json:"latencyMs"`
	LatencyMedianMS *float64 `json:"latencyMedianMs"`
	Uptime24h       *float64 `json:"uptime24h"`
	Uptime7d        *float64 `json:"uptime7d"`
	Checks7d        int      `json:"checks7d"`
	ExitIP          *string  `json:"exitIp"`
	SourcesCount    int      `json:"sourcesCount"`
	FirstSeen       string   `json:"firstSeen"`
	LastChecked     string   `json:"lastChecked"`
}

// Filters restrict proxy results. Nil numeric and boolean fields do not filter.
// CheckedWithinMin defaults to 30 when nil and must be in the range 1 through 1440.
type Filters struct {
	Protocol         string
	Country          string
	Anonymity        string
	HTTPS            *bool
	MaxLatencyMS     *int
	MinUptime7d      *int
	MinChecks7d      *int
	CheckedWithinMin *int
	Limit            *int
}

// ClientOptions configures a Client. Transport is useful for deterministic tests;
// HTTPClient takes precedence when both are provided. Now defaults to time.Now.
type ClientOptions struct {
	Source     Source
	APIURL     string
	GitHubURL  string
	HTTPClient *http.Client
	Transport  http.RoundTripper
	Now        func() time.Time
	Timeout    time.Duration
}

// Bool returns a bool pointer for optional Filters fields.
func Bool(value bool) *bool { return &value }

// Int returns an int pointer for optional Filters fields.
func Int(value int) *int { return &value }

// ToProxyURL formats a proxy as protocol://ip:port.
func ToProxyURL(proxy Proxy) string {
	return fmt.Sprintf("%s://%s:%d", proxy.Protocol, proxy.IP, proxy.Port)
}

// ProxyURL is an alias for ToProxyURL.
func ProxyURL(proxy Proxy) string { return ToProxyURL(proxy) }
