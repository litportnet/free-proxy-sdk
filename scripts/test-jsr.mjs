import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { execFileSync } from 'node:child_process'

const root = new URL('..', import.meta.url)
execFileSync(process.execPath, ['scripts/build-jsr.mjs', '--check'], { cwd: root, stdio: 'inherit' })

const api = JSON.parse(await readFile(new URL('../fixtures/api-snapshot.json', import.meta.url)))
const github = JSON.parse(await readFile(new URL('../fixtures/github-proxies.json', import.meta.url)))
const expected = JSON.parse(await readFile(new URL('../fixtures/expected-proxies.json', import.meta.url)))
const artifact = await readFile(new URL('../packages/jsr/mod.js', import.meta.url), 'utf8')
assert.doesNotMatch(artifact, /\brequire\s*\(|\bmodule\.exports\b|\bexports\./)

const { Client } = await import(new URL('../packages/jsr/mod.js', import.meta.url))
const now = () => new Date('2026-09-10T00:00:00.000Z')
const transport = body => async () => ({ status: 200, headers: { 'cache-control': 'max-age=60' }, body })
assert.deepEqual(await new Client({ now, transport: transport(api) }).getProxies(), expected)
assert.deepEqual(await new Client({ source: 'github', now, transport: transport(github) }).getProxies(), expected)
console.log('JSR generation drift and API/GitHub fixture parity passed')
