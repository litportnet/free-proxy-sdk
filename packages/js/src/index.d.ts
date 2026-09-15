export type Protocol = 'http' | 'socks4' | 'socks5'
export type Anonymity = 'transparent' | 'anonymous' | 'elite' | 'unknown'
export interface Proxy { protocol: Protocol; ip: string; port: number; url: string; country: string | null; region: string | null; city: string | null; timezone: string | null; asn: number | null; asnOrg: string | null; anonymity: Anonymity; https: boolean | null; latencyMs: number | null; latencyMedianMs: number | null; uptime24h: number | null; uptime7d: number | null; checks7d: number; exitIp: string | null; sourcesCount: number; firstSeen: string; lastChecked: string }
export interface Filters { protocol?: Protocol; country?: string; anonymity?: Anonymity; https?: boolean; maxLatencyMs?: number; minUptime7d?: number; minChecks7d?: number; checkedWithinMin?: number; limit?: number }
export interface ClientOptions { source?: 'api' | 'github'; apiUrl?: string; githubUrl?: string; transport?: (url: string, options: unknown) => unknown; now?: () => Date; timeoutMs?: number }
export class FreeProxyError extends Error {}
export class TimeoutError extends FreeProxyError {}
export class HttpError extends FreeProxyError { status: number }
export class NotModifiedWithoutCacheError extends FreeProxyError {}
export class SnapshotValidationError extends FreeProxyError {}
export class SnapshotTruncatedError extends FreeProxyError {}
export class FilterValidationError extends FreeProxyError {}
export class Client { constructor(options?: ClientOptions); getProxies(filters?: Filters): Promise<Proxy[]>; pickBest(n: number, filters?: Filters): Promise<Proxy[]>; rotate(filters?: Filters): Promise<IterableIterator<Proxy>> }
export function getProxies(filters?: Filters): Promise<Proxy[]>
export function pickBest(n: number, filters?: Filters): Promise<Proxy[]>
export function rotate(filters?: Filters): Promise<IterableIterator<Proxy>>
export function toProxyUrl(proxy: Proxy): string
export function withProxyAgent<T>(proxy: Proxy, ProxyAgentCtor: new (url: string) => T): T
export const DEFAULT_API_URL: string
export const DEFAULT_GITHUB_URL: string
