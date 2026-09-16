// Run with Node or Deno; exercise the package's native fetch, not an injected transport.
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { createServer } from 'node:http'
import { Client, HttpError, FilterValidationError, TimeoutError } from '../packages/jsr/mod.js'

const read = async name => JSON.parse(await readFile(new URL(`../fixtures/${name}.json`, import.meta.url)))
const api = await read('api-snapshot')
const github = await read('github-proxies')
const expected = await read('expected-proxies')
const now = () => new Date('2026-09-10T00:00:00Z')
let requests = 0
const server = createServer((req, res) => {
  requests++
  if (req.url === '/timeout') return
  if (req.url === '/error') { res.writeHead(503).end(); return }
  res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'max-age=60' })
  res.end(JSON.stringify(req.url === '/github' ? github : api))
})
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
const base = `http://127.0.0.1:${server.address().port}`
try {
  const client = new Client({ apiUrl: base, now })
  assert.deepEqual(await client.getProxies(), expected)
  const count = requests
  assert.equal((await client.pickBest(1, { protocol: 'socks5' }))[0].protocol, 'socks5')
  assert.equal(requests, count, 'second call uses the bounded cache')
  assert.deepEqual(await new Client({ source: 'github', githubUrl: `${base}/github`, now }).getProxies(), expected)
  await assert.rejects(client.getProxies({ checkedWithinMin: 0 }), FilterValidationError)
  await assert.rejects(new Client({ apiUrl: `${base}/error`, now }).getProxies(), HttpError)
  await assert.rejects(new Client({ apiUrl: `${base}/timeout`, timeoutMs: 25, now }).getProxies(), TimeoutError)
  console.log('Native fetch, normalization, filters, cache, HTTP errors and timeout passed')
} finally {
  server.closeAllConnections()
  await new Promise(resolve => server.close(resolve))
}
