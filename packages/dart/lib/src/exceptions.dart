/// The base class for every exception thrown by [LitportFreeProxyClient]
/// (from `client.dart`).
///
/// Catch this type to handle any client failure uniformly, or catch one of
/// its subclasses to handle a specific failure mode.
class FreeProxyException implements Exception {
  /// A human-readable description of the failure.
  final String message;

  /// Creates a [FreeProxyException] with the given [message].
  const FreeProxyException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when a snapshot request does not complete within the configured
/// timeout.
///
/// Named `ProxyTimeoutException`, rather than `TimeoutException`, to avoid
/// clashing with `dart:async`'s [TimeoutException].
class ProxyTimeoutException extends FreeProxyException {
  /// Creates a [ProxyTimeoutException] with the given [message].
  const ProxyTimeoutException(super.message);
}

/// Thrown when the snapshot endpoint responds with an HTTP status code
/// outside the 200-299 range.
class HttpStatusException extends FreeProxyException {
  /// The HTTP status code returned by the snapshot endpoint.
  final int statusCode;

  /// Creates an [HttpStatusException] for the given [statusCode].
  HttpStatusException(this.statusCode)
      : super('Snapshot request failed with HTTP $statusCode');
}

/// Thrown when the snapshot envelope, or one of its proxy rows, is
/// malformed, or when the response body cannot be parsed as JSON.
class SnapshotValidationException extends FreeProxyException {
  /// Creates a [SnapshotValidationException] with the given [message].
  const SnapshotValidationException(super.message);
}

/// Thrown when the snapshot envelope is explicitly marked as truncated.
class SnapshotTruncatedException extends FreeProxyException {
  /// Creates a [SnapshotTruncatedException].
  const SnapshotTruncatedException() : super('Snapshot is truncated');
}

/// Thrown when a [ProxyFilters] value (from `filters.dart`), or another
/// client argument such as `timeout` or the `count` passed to
/// [LitportFreeProxyClient.pickBest], fails validation.
class FilterValidationException extends FreeProxyException {
  /// Creates a [FilterValidationException] with the given [message].
  const FilterValidationException(super.message);
}
