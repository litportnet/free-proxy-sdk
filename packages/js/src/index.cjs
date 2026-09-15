'use strict'

const DEFAULT_API_URL = 'https://litport.net/api/free-proxy/snapshot?checkedWithinMin=1440'
const DEFAULT_GITHUB_URL = 'https://raw.githubusercontent.com/litportnet/free-proxy-list/live/proxies/all.json'
const PROTOCOLS = new Set(['http', 'socks4', 'socks5'])
const ANONYMITY = new Set(['transparent', 'anonymous', 'elite', 'unknown'])
const FIELDS = require('./fields.generated.cjs')
const FIELD_BY_JS = Object.fromEntries(FIELDS.map(field => [field.js, field]))

class FreeProxyError extends Error { constructor(message) { super(message); this.name = this.constructor.name } }
class TimeoutError extends FreeProxyError {}
class HttpError extends FreeProxyError { constructor(status, message = `Snapshot request failed with HTTP ${status}`) { super(message); this.status = status } }
class NotModifiedWithoutCacheError extends FreeProxyError {}
class SnapshotValidationError extends FreeProxyError {}
class SnapshotTruncatedError extends FreeProxyError {}
class FilterValidationError extends FreeProxyError {}

const clone = proxy => ({ ...proxy })
const asDate = value => {
  if (typeof value !== 'string' || value.length < 20 || !/(?:Z|[+-]\d\d:\d\d)$/.test(value)) return null
  const date = new Date(value)
  return Number.isFinite(date.getTime()) ? date : null
}
const isoTimestamp = value => asDate(value)?.toISOString() || null
const publicIpv4 = ip => {
  const parts = String(ip).split('.')
  if (parts.length !== 4 || parts.some(part => !/^\d+$/.test(part) || Number(part) > 255)) return false
  const value = parts.map(Number).reduce((total, part) => total * 256 + part, 0)
  const ranges = [[0x00000000, 8], [0x0a000000, 8], [0x64400000, 10], [0x7f000000, 8], [0xa9fe0000, 16], [0xac100000, 12], [0xc0000000, 24], [0xc0000200, 24], [0xc0a80000, 16], [0xc6120000, 15], [0xc6336400, 24], [0xcb007100, 24], [0xe0000000, 4], [0xf0000000, 4]]
  return !ranges.some(([network, prefix]) => Math.floor(value / 2 ** (32 - prefix)) === Math.floor(network / 2 ** (32 - prefix)))
}
const nullableString = value => value == null ? null : typeof value === 'string' ? value : undefined
const nullableNumber = value => value == null ? null : Number.isFinite(value) ? value : undefined
const header = (headers, name) => {
  if (!headers) return null
  if (typeof headers.get === 'function') return headers.get(name)
  return headers[name] || headers[name.toLowerCase()] || null
}
const normaliseResponse = async response => {
  try {
    let body = response.body
    if ((body === undefined || (body && typeof body.getReader === 'function')) && typeof response.json === 'function') body = await response.json()
    if (typeof body === 'string') body = JSON.parse(body)
    return { headers: response.headers, body }
  } catch (error) { throw new SnapshotValidationError('Malformed snapshot JSON') }
}
const cacheSeconds = response => Math.min(60, Math.max(0, Number(/max-age=(\d+)/i.exec(header(response.headers, 'cache-control') || '')?.[1] || 60)))

function validateFilters(filters = {}) {
  const allowed = new Set(['protocol', 'country', 'anonymity', 'https', 'maxLatencyMs', 'minUptime7d', 'minChecks7d', 'checkedWithinMin', 'limit'])
  for (const key of Object.keys(filters)) if (!allowed.has(key)) throw new FilterValidationError(`Unknown filter: ${key}`)
  if (filters.protocol != null && !PROTOCOLS.has(filters.protocol)) throw new FilterValidationError('protocol must be http, socks4, or socks5')
  if (filters.country != null && !/^[a-z]{2}$/i.test(filters.country)) throw new FilterValidationError('country must be a two-letter code')
  if (filters.anonymity != null && !ANONYMITY.has(filters.anonymity)) throw new FilterValidationError('Invalid anonymity value')
  if (filters.https != null && typeof filters.https !== 'boolean') throw new FilterValidationError('https must be boolean')
  for (const key of ['maxLatencyMs', 'minUptime7d', 'minChecks7d', 'limit']) if (filters[key] != null && (!Number.isInteger(filters[key]) || filters[key] < 0)) throw new FilterValidationError(`${key} must be a non-negative integer`)
  const checkedWithinMin = filters.checkedWithinMin == null ? 30 : filters.checkedWithinMin
  if (!Number.isInteger(checkedWithinMin) || checkedWithinMin < 1 || checkedWithinMin > 1440) throw new FilterValidationError('checkedWithinMin must be an integer from 1 to 1440')
  return { ...filters, country: filters.country?.toLowerCase(), checkedWithinMin }
}

function mapRow(row, source) {
  if (!row || typeof row !== 'object') throw new SnapshotValidationError('Snapshot contains an invalid proxy row')
  const get = jsName => row[FIELD_BY_JS[jsName][source]]
  const protocol = get('protocol')
  const ip = get('ip')
  const port = get('port')
  const firstSeen = get('firstSeen')
  const lastChecked = get('lastChecked')
  const country = get('country')
  const asnValue = get('asn')
  const asn = asnValue == null ? null : typeof asnValue === 'number' ? asnValue : Number(String(asnValue).replace(/^AS/i, ''))
  const apiLatency = get('latencyMs'); const apiMedianLatency = get('latencyMedianMs')
  const output = {
    protocol, ip, port, url: `${protocol}://${ip}:${port}`,
    country: country == null ? null : String(country).toLowerCase(),
    region: get('region'), city: get('city'), timezone: get('timezone'), asn, asnOrg: get('asnOrg'), anonymity: get('anonymity'), https: get('https'),
    latencyMs: source === 'api' && apiLatency != null ? Math.round(apiLatency) : apiLatency, latencyMedianMs: apiMedianLatency, uptime24h: get('uptime24h'), uptime7d: get('uptime7d'), checks7d: get('checks7d'),
    exitIp: get('exitIp'), sourcesCount: get('sourcesCount'), firstSeen: isoTimestamp(firstSeen), lastChecked: isoTimestamp(lastChecked),
  }
  if (!PROTOCOLS.has(protocol) || !publicIpv4(ip) || !Number.isInteger(port) || port < 1 || port > 65535 || !ANONYMITY.has(output.anonymity) || output.firstSeen === null || output.lastChecked === null) throw new SnapshotValidationError('Snapshot contains an invalid proxy row')
  for (const key of ['country', 'region', 'city', 'timezone', 'asnOrg', 'exitIp']) if (nullableString(output[key]) === undefined) throw new SnapshotValidationError(`Invalid ${key}`)
  if (output.country && !/^[a-z]{2}$/.test(output.country)) throw new SnapshotValidationError('Invalid country')
  if (!(output.asn === null || (Number.isInteger(output.asn) && output.asn >= 0))) throw new SnapshotValidationError('Invalid ASN')
  if (!(output.https === null || typeof output.https === 'boolean')) throw new SnapshotValidationError('Invalid https value')
  for (const key of ['latencyMs', 'latencyMedianMs', 'uptime24h', 'uptime7d']) if (nullableNumber(output[key]) === undefined) throw new SnapshotValidationError(`Invalid ${key}`)
  if (!Number.isInteger(output.checks7d) || output.checks7d < 0 || !Number.isInteger(output.sourcesCount) || output.sourcesCount < 0) throw new SnapshotValidationError('Invalid count')
  if (output.checks7d < 50) output.uptime7d = null
  return output
}

const sortProxies = rows => [...rows].sort((a, b) => (a.uptime7d == null) - (b.uptime7d == null) || (b.uptime7d ?? 0) - (a.uptime7d ?? 0) || (a.latencyMs == null) - (b.latencyMs == null) || (a.latencyMs ?? 0) - (b.latencyMs ?? 0) || a.url.localeCompare(b.url))

class Client {
  constructor({ source = 'api', apiUrl = DEFAULT_API_URL, githubUrl = DEFAULT_GITHUB_URL, transport = globalThis.fetch, now = () => new Date(), timeoutMs = 10000 } = {}) {
    if (!['api', 'github'].includes(source)) throw new FilterValidationError('source must be api or github')
    if (typeof transport !== 'function') throw new TypeError('transport must be a function')
    this.source = source; this.apiUrl = apiUrl; this.githubUrl = githubUrl; this.transport = transport; this.now = now; this.timeoutMs = timeoutMs; this.cache = null
  }
  async _request(url, etag) {
    const controller = typeof AbortController === 'undefined' ? null : new AbortController()
    let timerId
    const timer = new Promise((_, reject) => { timerId = setTimeout(() => { controller?.abort(); reject(new TimeoutError(`Snapshot request timed out after ${this.timeoutMs}ms`)) }, this.timeoutMs) })
    try { return await Promise.race([Promise.resolve(this.transport(url, { headers: etag ? { 'If-None-Match': etag } : {}, signal: controller?.signal })).catch(error => { if (error instanceof FreeProxyError) throw error; throw new FreeProxyError(`Snapshot request failed: ${error.message || error}`) }), timer]) } finally { clearTimeout(timerId) }
  }
  async _rows() {
    const now = this.now(); const nowMs = now.getTime()
    if (this.cache && nowMs < this.cache.expiresAt) { this._validateGeneratedAt(this.cache.generatedAt, nowMs); return this.cache.rows }
    const response = await this._request(this.source === 'api' ? this.apiUrl : this.githubUrl, this.cache?.etag)
    const status = response.status == null ? 200 : response.status
    if (status === 304) {
      if (!this.cache) throw new NotModifiedWithoutCacheError('Received 304 without a cached snapshot')
      this._validateGeneratedAt(this.cache.generatedAt, nowMs)
      this.cache.expiresAt = nowMs + cacheSeconds(response) * 1000
      return this.cache.rows
    }
    if (status === 429) throw new HttpError(429)
    if (status < 200 || status >= 300) throw new HttpError(status)
    const parsed = await normaliseResponse(response)
    let rows
    if (this.source === 'api') {
      const snapshot = parsed.body
      if (!snapshot || !Array.isArray(snapshot.proxies) || !Number.isInteger(snapshot.count) || snapshot.count !== snapshot.proxies.length || (snapshot.truncated != null && typeof snapshot.truncated !== 'boolean') || snapshot.truncated === true) {
        if (snapshot?.truncated) throw new SnapshotTruncatedError('Snapshot is truncated')
        throw new SnapshotValidationError('Malformed snapshot envelope')
      }
      const generatedAt = snapshot.generatedAt
      this._validateGeneratedAt(generatedAt, nowMs)
      rows = snapshot.proxies.map(row => mapRow(row, 'api'))
    } else {
      if (!Array.isArray(parsed.body)) throw new SnapshotValidationError('Malformed GitHub proxy list')
      rows = parsed.body.map(row => mapRow(row, 'github'))
    }
    this.cache = { rows, etag: header(response.headers, 'etag'), generatedAt: this.source === 'api' ? parsed.body.generatedAt : null, expiresAt: nowMs + cacheSeconds(response) * 1000 }
    return rows
  }
  _validateGeneratedAt(value, nowMs) { if (this.source !== 'api') return; const generatedAt = asDate(value); if (!generatedAt || generatedAt.getTime() > nowMs + 5000 || generatedAt.getTime() < nowMs - 120000) throw new SnapshotValidationError('Snapshot generatedAt is outside the accepted window') }
  async getProxies(filters = {}) {
    const checked = validateFilters(filters); const rowsSnapshot = await this._rows(); const nowMs = this.now().getTime(); const cutoff = nowMs - checked.checkedWithinMin * 60000
    let rows = rowsSnapshot.filter(row => { const checkedAt = asDate(row.lastChecked)?.getTime(); return checkedAt >= cutoff && checkedAt <= nowMs + 5000 })
    if (checked.protocol) rows = rows.filter(row => row.protocol === checked.protocol)
    if (checked.country) rows = rows.filter(row => row.country === checked.country)
    if (checked.anonymity) rows = rows.filter(row => row.anonymity === checked.anonymity)
    if (checked.https != null) rows = rows.filter(row => row.https === checked.https)
    if (checked.maxLatencyMs != null) rows = rows.filter(row => row.latencyMs != null && row.latencyMs <= checked.maxLatencyMs)
    if (checked.minUptime7d != null) rows = rows.filter(row => row.uptime7d != null && row.uptime7d >= checked.minUptime7d)
    if (checked.minChecks7d != null) rows = rows.filter(row => row.checks7d >= checked.minChecks7d)
    return sortProxies(rows).slice(0, checked.limit).map(clone)
  }
  async pickBest(n, filters = {}) { if (!Number.isInteger(n) || n < 0) throw new FilterValidationError('n must be a non-negative integer'); return (await this.getProxies(filters)).slice(0, n) }
  async rotate(filters = {}) {
    const checked = validateFilters(filters); const rows = await this.getProxies(checked); let index = 0
    return { next: () => {
      const nowMs = this.now().getTime(); const cutoff = nowMs - checked.checkedWithinMin * 60000
      for (let tries = 0; tries < rows.length; tries += 1) { const row = rows[index % rows.length]; index += 1; const checkedAt = asDate(row.lastChecked)?.getTime(); if (checkedAt >= cutoff && checkedAt <= nowMs + 5000) return { done: false, value: clone(row) } }
      return { done: true, value: undefined }
    }, [Symbol.iterator]() { return this } }
  }
}

const toProxyUrl = proxy => `${proxy.protocol}://${proxy.ip}:${proxy.port}`
const withProxyAgent = (proxy, ProxyAgentCtor) => new ProxyAgentCtor(toProxyUrl(proxy))
const defaultClient = new Client()
const getProxies = filters => defaultClient.getProxies(filters)
const pickBest = (n, filters = {}) => defaultClient.pickBest(n, filters)
const rotate = filters => defaultClient.rotate(filters)

module.exports = { Client, FreeProxyError, TimeoutError, HttpError, NotModifiedWithoutCacheError, SnapshotValidationError, SnapshotTruncatedError, FilterValidationError, getProxies, pickBest, rotate, toProxyUrl, withProxyAgent, DEFAULT_API_URL, DEFAULT_GITHUB_URL }
