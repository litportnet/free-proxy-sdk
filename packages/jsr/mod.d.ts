/**
 * A dependency-free client for the Litport public free-proxy snapshot.
 *
 * @module
 */

/** Supported proxy transport protocols. */
export type Protocol = 'http' | 'socks4' | 'socks5'

/** Proxy anonymity classifications reported by the source snapshot. */
export type Anonymity = 'transparent' | 'anonymous' | 'elite' | 'unknown'

/**
 * A validated public proxy observation.
 *
 * Timestamp values are ISO 8601 UTC strings. Numeric latency values are in
 * milliseconds and uptime values are source-reported percentages.
 */
export interface Proxy {
  /** Proxy transport protocol. */
  protocol: Protocol
  /** Public IPv4 address of the proxy endpoint. */
  ip: string
  /** TCP port from 1 through 65535. */
  port: number
  /** Canonical proxy URL, such as `socks5://198.51.100.8:1080`. */
  url: string
  /** Lowercase ISO 3166-1 alpha-2 country code, when known. */
  country: string | null
  /** Geographic region, when reported by the source. */
  region: string | null
  /** Geographic city, when reported by the source. */
  city: string | null
  /** IANA timezone name, when reported by the source. */
  timezone: string | null
  /** Autonomous system number, when reported by the source. */
  asn: number | null
  /** Autonomous system organization name, when reported by the source. */
  asnOrg: string | null
  /** Source-reported proxy anonymity classification. */
  anonymity: Anonymity
  /** Whether the proxy supports HTTP CONNECT, or `null` when unmeasured. */
  https: boolean | null
  /** Latency of the most recent successful check in milliseconds, or `null` when unavailable. */
  latencyMs: number | null
  /** Median observed latency in milliseconds, or `null` when unavailable. */
  latencyMedianMs: number | null
  /** Uptime over the past 24 hours as a percentage, or `null` when unavailable. */
  uptime24h: number | null
  /** Uptime over seven days as a percentage, or `null` when fewer than 50 checks exist. */
  uptime7d: number | null
  /** Number of checks observed during the last seven days. */
  checks7d: number
  /** Public exit IP observed during a check, when available. */
  exitIp: string | null
  /** Number of independent source observations for this proxy. */
  sourcesCount: number
  /** ISO 8601 UTC timestamp of the first observation. */
  firstSeen: string
  /** ISO 8601 UTC timestamp of the latest validation check. */
  lastChecked: string
}

/**
 * Filters applied after the snapshot has been fetched and validated.
 *
 * Invalid values and unknown keys throw {@link FilterValidationError}. Records
 * with `null` numeric measurements do not pass numeric filters.
 */
export interface Filters {
  /** Require this proxy protocol. */
  protocol?: Protocol
  /** Require a two-letter country code; input is normalized to lowercase. */
  country?: string
  /** Require this anonymity classification. */
  anonymity?: Anonymity
  /** Require measured HTTP CONNECT support to equal this value. */
  https?: boolean
  /** Keep records whose latest latency is at most this many milliseconds; must be a non-negative integer. */
  maxLatencyMs?: number
  /** Keep records whose seven-day uptime percentage is at least this value; must be a non-negative integer. */
  minUptime7d?: number
  /** Keep records with at least this many seven-day checks; must be a non-negative integer. */
  minChecks7d?: number
  /**
   * Require checks within this many minutes, from 1 through 1440.
   *
   * @defaultValue 30
   */
  checkedWithinMin?: number
  /**
   * Return at most this many matching records; must be a non-negative integer.
   * Zero is allowed.
   *
   * @defaultValue all matching records
   */
  limit?: number
}

/** Configuration for a {@link Client}. */
export interface ClientOptions {
  /**
   * Snapshot source to request.
   *
   * @defaultValue `'api'`
   */
  source?: 'api' | 'github'
  /**
   * API snapshot URL used when `source` is `'api'`.
   *
   * @defaultValue {@link DEFAULT_API_URL}
   */
  apiUrl?: string
  /**
   * Raw GitHub dataset URL used when `source` is `'github'`.
   *
   * @defaultValue {@link DEFAULT_GITHUB_URL}
   */
  githubUrl?: string
  /**
   * Fetch-compatible request function, primarily useful for tests or custom
   * runtimes. It receives the URL and request options and must return the
   * response object or a promise for it.
   *
   * @defaultValue global `fetch`
   */
  transport?: (url: string, options: unknown) => unknown
  /**
   * Clock used for snapshot and record freshness checks.
   *
   * @defaultValue `() => new Date()`
   */
  now?: () => Date
  /**
   * Per-request timeout in milliseconds.
   *
   * @defaultValue 10000
   */
  timeoutMs?: number
}

/**
 * Base error class for failures raised by this SDK, including wrapped transport
 * failures that are not timeouts.
 */
export class FreeProxyError extends Error {}

/** Raised when a snapshot request exceeds the configured request timeout. */
export class TimeoutError extends FreeProxyError {}

/** Raised when a snapshot endpoint returns an unsuccessful HTTP status, including 429. */
export class HttpError extends FreeProxyError {
  /** HTTP response status returned by the source endpoint. */
  status: number
}

/** Raised when a source returns HTTP 304 before this client has a cached snapshot. */
export class NotModifiedWithoutCacheError extends FreeProxyError {}

/** Raised when a snapshot envelope or proxy record is malformed or expired. */
export class SnapshotValidationError extends FreeProxyError {}

/** Raised when a snapshot explicitly reports that its proxy list is truncated. */
export class SnapshotTruncatedError extends FreeProxyError {}

/** Raised when supplied filters or client options have invalid values. */
export class FilterValidationError extends FreeProxyError {}

/**
 * Client with client-owned, in-memory ETag cache for one proxy snapshot source.
 *
 * The cache is capped at 60 seconds, while every call still applies the
 * `checkedWithinMin` freshness filter.
 *
 * @example Create a GitHub-backed client.
 * ```ts
 * const client = new Client({ source: 'github' })
 * const proxies = await client.getProxies({ protocol: 'socks5' })
 * ```
 */
export class Client {
  /**
   * Creates a client with optional source, transport, clock, and timeout overrides.
   *
   * @throws {@link FilterValidationError} when `source` is invalid.
   * @throws {TypeError} when no usable transport is available.
   */
  constructor(options?: ClientOptions)

  /**
   * Fetches, validates, filters, and sorts proxies by seven-day uptime
   * descending, then latency ascending, then URL.
   *
   * Returned records are copies and may be safely mutated by the caller.
   *
   * @example
   * ```ts
   * const proxies = await client.getProxies({ country: 'us', maxLatencyMs: 500 })
   * ```
   * @throws {@link FreeProxyError} when the transport fails outside a timeout.
   * @throws {@link TimeoutError} when the request times out.
   * @throws {@link HttpError} for unsuccessful HTTP responses.
   * @throws {@link NotModifiedWithoutCacheError} for an uncached 304 response.
   * @throws {@link SnapshotValidationError} for malformed, future, or stale snapshots.
   * @throws {@link SnapshotTruncatedError} when the source reports truncation.
   * @throws {@link FilterValidationError} for invalid filters.
   */
  getProxies(filters?: Filters): Promise<Proxy[]>

  /**
   * Returns the first `n` records from the same ordered result as {@link getProxies}.
   *
   * @example
   * ```ts
   * const best = await client.pickBest(3, { protocol: 'http' })
   * ```
   * @throws {@link FreeProxyError} when snapshot retrieval fails.
   * @throws {@link TimeoutError} when the request times out.
   * @throws {@link HttpError} for unsuccessful HTTP responses.
   * @throws {@link NotModifiedWithoutCacheError} for an uncached 304 response.
   * @throws {@link SnapshotValidationError} for malformed, future, or stale snapshots.
   * @throws {@link SnapshotTruncatedError} when the source reports truncation.
   * @throws {@link FilterValidationError} when `n` is not a non-negative integer or filters are invalid.
   */
  pickBest(n: number, filters?: Filters): Promise<Proxy[]>

  /**
   * Fetches one ordered snapshot and returns a synchronous round-robin iterator
   * over that fixed membership. Each `next()` rechecks record freshness and
   * stops when no remaining record is fresh; recreate the iterator to refresh
   * membership.
   *
   * @example
   * ```ts
   * const proxies = await client.rotate({ checkedWithinMin: 15 })
   * const next = proxies.next()
   * ```
   * @throws {@link FreeProxyError} when initial snapshot retrieval fails.
   * @throws {@link TimeoutError} when the initial request times out.
   * @throws {@link HttpError} for unsuccessful HTTP responses.
   * @throws {@link NotModifiedWithoutCacheError} for an uncached 304 response.
   * @throws {@link SnapshotValidationError} for malformed, future, or stale snapshots.
   * @throws {@link SnapshotTruncatedError} when the source reports truncation.
   * @throws {@link FilterValidationError} for invalid filters.
   */
  rotate(filters?: Filters): Promise<IterableIterator<Proxy>>
}

/**
 * Fetches proxies through the shared default API client.
 *
 * @example
 * ```ts
 * import { getProxies } from '@litportnet/free-proxy-sdk'
 * const proxies = await getProxies({ checkedWithinMin: 10 })
 * ```
 * @throws {@link FreeProxyError} when the transport fails outside a timeout.
 * @throws {@link TimeoutError} when the request times out.
 * @throws {@link HttpError} for unsuccessful HTTP responses.
 * @throws {@link NotModifiedWithoutCacheError} for an uncached 304 response.
 * @throws {@link SnapshotValidationError} for malformed, future, or stale snapshots.
 * @throws {@link SnapshotTruncatedError} when the source reports truncation.
 * @throws {@link FilterValidationError} for invalid filters.
 */
export function getProxies(filters?: Filters): Promise<Proxy[]>

/**
 * Returns the first `n` proxies from the shared default API client.
 *
 * @example
 * ```ts
 * import { pickBest } from '@litportnet/free-proxy-sdk'
 * const proxies = await pickBest(5, { minUptime7d: 95 })
 * ```
 * @throws {@link FreeProxyError} when snapshot retrieval fails.
 * @throws {@link TimeoutError} when the request times out.
 * @throws {@link HttpError} for unsuccessful HTTP responses.
 * @throws {@link NotModifiedWithoutCacheError} for an uncached 304 response.
 * @throws {@link SnapshotValidationError} for malformed, future, or stale snapshots.
 * @throws {@link SnapshotTruncatedError} when the source reports truncation.
 * @throws {@link FilterValidationError} when `n` or filters are invalid.
 */
export function pickBest(n: number, filters?: Filters): Promise<Proxy[]>

/**
 * Returns a fixed-membership, synchronous round-robin iterator from the shared
 * default API client after fetching its snapshot.
 *
 * @example
 * ```ts
 * import { rotate } from '@litportnet/free-proxy-sdk'
 * const iterator = await rotate({ protocol: 'socks5' })
 * const first = iterator.next().value
 * ```
 * @throws {@link FreeProxyError} when initial snapshot retrieval fails.
 * @throws {@link TimeoutError} when the initial request times out.
 * @throws {@link HttpError} for unsuccessful HTTP responses.
 * @throws {@link NotModifiedWithoutCacheError} for an uncached 304 response.
 * @throws {@link SnapshotValidationError} for malformed, future, or stale snapshots.
 * @throws {@link SnapshotTruncatedError} when the source reports truncation.
 * @throws {@link FilterValidationError} for invalid filters.
 */
export function rotate(filters?: Filters): Promise<IterableIterator<Proxy>>

/**
 * Builds the canonical URL for a validated proxy.
 *
 * @example
 * ```ts
 * const url = toProxyUrl(proxy) // 'http://198.51.100.8:8080'
 * ```
 */
export function toProxyUrl(proxy: Proxy): string

/**
 * Constructs an agent using a caller-supplied proxy-agent constructor.
 *
 * The caller is responsible for choosing a constructor compatible with the
 * proxy's protocol.
 *
 * @typeParam T Type returned by the supplied agent constructor.
 * @example
 * ```ts
 * const agent = withProxyAgent(proxy, ProxyAgent)
 * ```
 */
export function withProxyAgent<T>(proxy: Proxy, ProxyAgentCtor: new (url: string) => T): T

/** Default API snapshot URL used by {@link Client} and top-level helpers. */
export const DEFAULT_API_URL: string

/** Default raw GitHub dataset URL used when a client selects the GitHub source. */
export const DEFAULT_GITHUB_URL: string
