package freeproxy

import (
	"fmt"
	"time"
)

// FreeProxyError is the common interface implemented by all SDK errors.
type FreeProxyError interface {
	error
	freeProxyError()
}

// TimeoutError reports that a snapshot request exceeded the configured timeout.
type TimeoutError struct{ Timeout time.Duration }

func (e *TimeoutError) Error() string {
	return fmt.Sprintf("snapshot request timed out after %s", e.Timeout)
}
func (*TimeoutError) freeProxyError() {}

// HTTPError reports a non-successful snapshot response.
type HTTPError struct{ StatusCode int }

func (e *HTTPError) Error() string {
	return fmt.Sprintf("snapshot request failed with HTTP %d", e.StatusCode)
}
func (*HTTPError) freeProxyError() {}

// NotModifiedWithoutCacheError reports a 304 response received before a snapshot was cached.
type NotModifiedWithoutCacheError struct{}

func (*NotModifiedWithoutCacheError) Error() string   { return "received 304 without a cached snapshot" }
func (*NotModifiedWithoutCacheError) freeProxyError() {}

// SnapshotValidationError reports a malformed, stale, or unsafe snapshot.
type SnapshotValidationError struct{ Message string }

func (e *SnapshotValidationError) Error() string { return e.Message }
func (*SnapshotValidationError) freeProxyError() {}

// SnapshotTruncatedError reports an API snapshot explicitly marked as truncated.
type SnapshotTruncatedError struct{}

func (*SnapshotTruncatedError) Error() string   { return "snapshot is truncated" }
func (*SnapshotTruncatedError) freeProxyError() {}

// FilterValidationError reports invalid filter or client option values.
type FilterValidationError struct{ Message string }

func (e *FilterValidationError) Error() string { return e.Message }
func (*FilterValidationError) freeProxyError() {}

// RequestError reports a transport error that was not a timeout.
type RequestError struct{ Err error }

func (e *RequestError) Error() string { return "snapshot request failed: " + e.Err.Error() }
func (e *RequestError) Unwrap() error { return e.Err }
func (*RequestError) freeProxyError() {}
