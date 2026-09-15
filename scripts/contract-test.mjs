import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import { createRequire } from 'node:module'

const api = JSON.parse(await readFile(new URL('../fixtures/api-snapshot.json', import.meta.url)))
const github = JSON.parse(await readFile(new URL('../fixtures/github-proxies.json', import.meta.url)))
const expected = JSON.parse(await readFile(new URL('../fixtures/expected-proxies.json', import.meta.url)))
const fields = JSON.parse(await readFile(new URL('../spec/fields.json', import.meta.url))).fields
const now = () => new Date('2026-09-10T00:00:00.000Z')
const require = createRequire(import.meta.url)
const { Client } = require('../packages/js/src/index.cjs')
const response = body => async () => ({ status: 200, headers: { 'cache-control': 'max-age=60' }, body })
assert.deepEqual(await new Client({ now, transport: response(api) }).getProxies(), expected)
assert.deepEqual(await new Client({ source: 'github', now, transport: response(github) }).getProxies(), expected)

const python = `import json,sys; from datetime import datetime,timezone; from pathlib import Path; sys.path.insert(0,'packages/python/src'); from litport_free_proxy_sdk import Client; root=Path('.'); now=lambda:datetime(2026,9,10,tzinfo=timezone.utc); load=lambda n:json.loads((root/'fixtures'/n).read_text()); transport=lambda body:lambda *_:(200, {'Cache-Control':'max-age=60'}, body); api=Client(now=now,transport=transport(load('api-snapshot.json'))).get_proxies(); github=Client(source='github',now=now,transport=transport(load('github-proxies.json'))).get_proxies(); print(json.dumps([[x.__dict__ for x in api],[x.__dict__ for x in github]], sort_keys=True))`
const [pythonApiRows, pythonGithubRows] = JSON.parse(execFileSync('python3', ['-c', python], { encoding: 'utf8' }))
const pythonExpected = row => Object.fromEntries(fields.map(field => [field.python, row[field.js]]))
assert.deepEqual(pythonApiRows, expected.map(pythonExpected))
assert.deepEqual(pythonGithubRows, expected.map(pythonExpected))
console.log('Cross-language API and GitHub fixture contract passed')
