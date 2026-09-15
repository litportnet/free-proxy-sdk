import assert from 'node:assert/strict'
import { createRequire } from 'node:module'
import { readFile } from 'node:fs/promises'
import { createServer } from 'node:http'
import test from 'node:test'
import { Client, HttpError, NotModifiedWithoutCacheError, SnapshotTruncatedError, TimeoutError, toProxyUrl } from '../src/index.cjs'
import { main as cliMain } from '../src/cli.cjs'

const fixture = async name => JSON.parse(await readFile(new URL(`../../../fixtures/${name}`, import.meta.url)))
const now = () => new Date('2026-09-10T00:00:00.000Z')
const transport = body => async () => ({ status: 200, headers: { etag: '"fixture"', 'cache-control': 'max-age=3600' }, body })

test('API and GitHub fixtures normalize to the same sorted contract', async () => {
  const expected = await fixture('expected-proxies.json')
  const api = new Client({ now, transport: transport(await fixture('api-snapshot.json')) })
  const github = new Client({ source: 'github', now, transport: transport(await fixture('github-proxies.json')) })
  assert.deepEqual(await api.getProxies(), expected)
  assert.deepEqual(await github.getProxies(), expected)
  assert.equal((await api.getProxies())[1].uptime7d, null)
})

test('filters, ranking, copies, and adapters have the public behavior', async () => {
  const client = new Client({ now, transport: transport(await fixture('api-snapshot.json')) })
  assert.deepEqual((await client.pickBest(1)).map(toProxyUrl), ['http://8.8.8.8:8080'])
  assert.equal((await client.getProxies({ protocol: 'socks5' })).length, 1)
  assert.equal((await client.getProxies({ minUptime7d: 90 })).length, 1)
  const rows = await client.getProxies(); rows[0].country = 'xx'
  assert.equal((await client.getProxies())[0].country, 'us')
  await assert.rejects(() => client.getProxies({ protocol: 'ftp' }), /protocol/)
})

test('rotate keeps its initial members but removes entries once they expire', async () => {
  let time = new Date('2026-09-10T00:00:00.000Z')
  const client = new Client({ now: () => time, transport: transport(await fixture('api-snapshot.json')) })
  const iterator = await client.rotate({ checkedWithinMin: 30 })
  assert.equal(iterator.next().value.ip, '8.8.8.8')
  time = new Date('2026-09-10T00:21:00.000Z')
  assert.equal(iterator.next().done, true)
})

test('typed request and snapshot failures are surfaced', async () => {
  await assert.rejects(() => new Client({ now, transport: async () => ({ status: 429, body: [] }) }).getProxies(), HttpError)
  await assert.rejects(() => new Client({ now, transport: async () => ({ status: 304, body: null }) }).getProxies(), NotModifiedWithoutCacheError)
  await assert.rejects(() => new Client({ now, transport: transport({ generatedAt: '2026-09-10T00:00:00.000Z', truncated: true, proxies: [] }) }).getProxies(), SnapshotTruncatedError)
  await assert.rejects(() => new Client({ now, timeoutMs: 1, transport: () => new Promise(() => {}) }).getProxies(), TimeoutError)
  await assert.rejects(() => new Client({ now, transport: transport({ generatedAt: '2026-09-10T00:00:00.000Z', count: 1, proxies: [{ nope: true }] }) }).getProxies(), /invalid proxy row/)
})

test('packed CommonJS and ESM exports load', async () => {
  const cjs = createRequire(import.meta.url)('../dist/index.cjs')
  const esm = await import('../dist/index.js')
  assert.equal(typeof cjs.Client, 'function')
  assert.equal(typeof esm.Client, 'function')
})

test('native fetch reads JSON and revalidates a local HTTP snapshot with 304', async () => {
  const body = JSON.stringify(await fixture('api-snapshot.json')); let requests = 0
  const server = createServer((request, response) => {
    requests += 1
    if (request.headers['if-none-match'] === '"local"') { response.writeHead(304, { ETag: '"local"', 'Cache-Control': 'max-age=0' }); return response.end() }
    response.writeHead(200, { 'content-type': 'application/json', ETag: '"local"', 'Cache-Control': 'max-age=0' }); response.end(body)
  })
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
  try {
    const client = new Client({ now, apiUrl: `http://127.0.0.1:${server.address().port}/snapshot` })
    assert.equal((await client.getProxies()).length, 2)
    assert.equal((await client.getProxies()).length, 2)
    assert.equal(requests, 2)
  } finally { await new Promise(resolve => server.close(resolve)) }
})

test('CLI applies source separately from filters and writes only requested data', async () => {
  const writes = []; const original = process.stdout.write; process.stdout.write = value => { writes.push(value); return true }
  try {
    const status = await cliMain(['--source', 'github', '--protocol', 'http', '--format', 'txt'], options => ({ getProxies: async filters => { assert.deepEqual(options, { source: 'github' }); assert.deepEqual(filters, { protocol: 'http' }); return [{ protocol: 'http', ip: '8.8.8.8', port: 8080 }] } }))
    assert.equal(status, 0); assert.deepEqual(writes, ['http://8.8.8.8:8080\n'])
  } finally { process.stdout.write = original }
})
