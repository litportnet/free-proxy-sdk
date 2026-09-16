package freeproxy

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

const fixtureTime = "2026-09-10T00:00:00.000Z"

type roundTripperFunc func(*http.Request) (*http.Response, error)

func (fn roundTripperFunc) RoundTrip(request *http.Request) (*http.Response, error) {
	return fn(request)
}

func fixture(t *testing.T, name string) []byte {
	t.Helper()
	body, err := os.ReadFile(filepath.Join("..", "..", "fixtures", name))
	if err != nil {
		t.Fatal(err)
	}
	return body
}

func staticResponse(status int, body []byte, headers http.Header) *http.Response {
	return &http.Response{StatusCode: status, Header: headers, Body: io.NopCloser(bytes.NewReader(body))}
}

func TestAPISnapshotAndGitHubFixtureParity(t *testing.T) {
	api := fixture(t, "api-snapshot.json")
	github := fixture(t, "github-proxies.json")
	expectedBytes := fixture(t, "expected-proxies.json")
	var expected []Proxy
	if err := json.Unmarshal(expectedBytes, &expected); err != nil {
		t.Fatal(err)
	}
	now, err := time.Parse(time.RFC3339Nano, fixtureTime)
	if err != nil {
		t.Fatal(err)
	}
	transport := func(body []byte) http.RoundTripper {
		return roundTripperFunc(func(*http.Request) (*http.Response, error) {
			return staticResponse(http.StatusOK, body, http.Header{"Cache-Control": []string{"max-age=3600"}, "ETag": []string{"\"fixture\""}}), nil
		})
	}
	apiClient, err := NewClient(ClientOptions{Now: func() time.Time { return now }, Transport: transport(api)})
	if err != nil {
		t.Fatal(err)
	}
	githubClient, err := NewClient(ClientOptions{Source: SourceGitHub, Now: func() time.Time { return now }, Transport: transport(github)})
	if err != nil {
		t.Fatal(err)
	}
	apiRows, err := apiClient.GetProxies(context.Background(), Filters{})
	if err != nil {
		t.Fatal(err)
	}
	githubRows, err := githubClient.GetProxies(context.Background(), Filters{})
	if err != nil {
		t.Fatal(err)
	}
	if !proxiesEqual(apiRows, expected) {
		t.Fatalf("API rows differ:\n got %#v\nwant %#v", apiRows, expected)
	}
	if !proxiesEqual(githubRows, expected) {
		t.Fatalf("GitHub rows differ:\n got %#v\nwant %#v", githubRows, expected)
	}
	if apiRows[1].Uptime7d != nil {
		t.Fatal("uptime7d must be null when checks7d is under 50")
	}
}

func TestFiltersCopiesAndRotation(t *testing.T) {
	clock := mustTime(t, fixtureTime)
	client := testClient(t, fixture(t, "api-snapshot.json"), func() time.Time { return clock })
	rows, err := client.PickBest(context.Background(), 1, Filters{})
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || ToProxyURL(rows[0]) != "http://8.8.8.8:8080" {
		t.Fatalf("unexpected pick: %#v", rows)
	}
	rows, err = client.GetProxies(context.Background(), Filters{Protocol: "socks5"})
	if err != nil || len(rows) != 1 {
		t.Fatalf("protocol filter: %#v, %v", rows, err)
	}
	rows, err = client.GetProxies(context.Background(), Filters{MinUptime7d: Int(90)})
	if err != nil || len(rows) != 1 {
		t.Fatalf("uptime filter: %#v, %v", rows, err)
	}
	rows, err = client.GetProxies(context.Background(), Filters{})
	if err != nil {
		t.Fatal(err)
	}
	*rows[0].Country = "xx"
	rows, err = client.GetProxies(context.Background(), Filters{})
	if err != nil {
		t.Fatal(err)
	}
	if *rows[0].Country != "us" {
		t.Fatal("returned records must not mutate cache")
	}
	if _, err := client.GetProxies(context.Background(), Filters{Protocol: "ftp"}); err == nil {
		t.Fatal("invalid protocol should fail")
	}
	if _, err := client.GetProxies(context.Background(), Filters{CheckedWithinMin: Int(0)}); err == nil {
		t.Fatal("invalid freshness should fail")
	}
	rotator, err := client.Rotate(context.Background(), Filters{CheckedWithinMin: Int(30)})
	if err != nil {
		t.Fatal(err)
	}
	row, ok := rotator.Next()
	if !ok || row.IP != "8.8.8.8" {
		t.Fatalf("unexpected rotation result: %#v, %t", row, ok)
	}
	clock = clock.Add(21 * time.Minute)
	if _, ok := rotator.Next(); ok {
		t.Fatal("expired rotation records should stop")
	}
}

func TestSnapshotAndRequestErrors(t *testing.T) {
	now := func() time.Time { return mustTime(t, fixtureTime) }
	newClient := func(status int, body []byte) *Client {
		client, err := NewClient(ClientOptions{Now: now, Transport: roundTripperFunc(func(*http.Request) (*http.Response, error) {
			return staticResponse(status, body, http.Header{}), nil
		})})
		if err != nil {
			t.Fatal(err)
		}
		return client
	}
	if _, err := newClient(http.StatusTooManyRequests, nil).GetProxies(context.Background(), Filters{}); !isError[*HTTPError](err) {
		t.Fatalf("wanted HTTPError, got %v", err)
	}
	if _, err := newClient(http.StatusNotModified, nil).GetProxies(context.Background(), Filters{}); !isError[*NotModifiedWithoutCacheError](err) {
		t.Fatalf("wanted missing-cache error, got %v", err)
	}
	if _, err := newClient(http.StatusOK, []byte(`{"generatedAt":"2026-09-10T00:00:00.000Z","count":0,"truncated":true,"proxies":[]}`)).GetProxies(context.Background(), Filters{}); !isError[*SnapshotTruncatedError](err) {
		t.Fatalf("wanted truncated error, got %v", err)
	}
	if _, err := newClient(http.StatusOK, []byte(`{"generatedAt":"2026-09-10T00:00:00.000Z","count":1,"proxies":[{"nope":true}]}`)).GetProxies(context.Background(), Filters{}); !isError[*SnapshotValidationError](err) {
		t.Fatalf("wanted validation error, got %v", err)
	}
	client, err := NewClient(ClientOptions{Now: now, Timeout: time.Millisecond, Transport: roundTripperFunc(func(request *http.Request) (*http.Response, error) {
		<-request.Context().Done()
		return nil, request.Context().Err()
	})})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := client.GetProxies(context.Background(), Filters{}); !isError[*TimeoutError](err) {
		t.Fatalf("wanted timeout error, got %v", err)
	}
}

func TestStaleCacheAndETagRevalidation(t *testing.T) {
	var mu sync.Mutex
	clock := mustTime(t, fixtureTime)
	requests := 0
	client, err := NewClient(ClientOptions{Now: func() time.Time { mu.Lock(); defer mu.Unlock(); return clock }, Transport: roundTripperFunc(func(request *http.Request) (*http.Response, error) {
		mu.Lock()
		defer mu.Unlock()
		requests++
		if request.Header.Get("If-None-Match") == "\"fixture\"" {
			return staticResponse(http.StatusNotModified, nil, http.Header{"Cache-Control": []string{"max-age=0"}}), nil
		}
		return staticResponse(http.StatusOK, fixture(t, "api-snapshot.json"), http.Header{"ETag": []string{"\"fixture\""}, "Cache-Control": []string{"max-age=0"}}), nil
	})})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := client.GetProxies(context.Background(), Filters{}); err != nil {
		t.Fatal(err)
	}
	mu.Lock()
	clock = clock.Add(3 * time.Minute)
	mu.Unlock()
	if _, err := client.GetProxies(context.Background(), Filters{}); !isError[*SnapshotValidationError](err) {
		t.Fatalf("wanted stale cache validation error, got %v", err)
	}
	mu.Lock()
	gotRequests := requests
	mu.Unlock()
	if gotRequests != 2 {
		t.Fatalf("wanted ETag revalidation, got %d requests", gotRequests)
	}
}

func testClient(t *testing.T, body []byte, now func() time.Time) *Client {
	t.Helper()
	client, err := NewClient(ClientOptions{Now: now, Transport: roundTripperFunc(func(*http.Request) (*http.Response, error) {
		return staticResponse(http.StatusOK, body, http.Header{"Cache-Control": []string{"max-age=3600"}}), nil
	})})
	if err != nil {
		t.Fatal(err)
	}
	return client
}

func mustTime(t *testing.T, value string) time.Time {
	t.Helper()
	parsed, err := time.Parse(time.RFC3339Nano, value)
	if err != nil {
		t.Fatal(err)
	}
	return parsed
}

func proxiesEqual(got, want []Proxy) bool {
	gotJSON, _ := json.Marshal(got)
	wantJSON, _ := json.Marshal(want)
	return bytes.Equal(gotJSON, wantJSON)
}

func isError[T error](err error) bool {
	var target T
	return errors.As(err, &target)
}
