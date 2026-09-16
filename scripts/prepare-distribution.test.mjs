import assert from 'node:assert/strict'
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'

import { prepare } from './prepare-distribution.mjs'

const sourceCommit = '0123456789abcdef0123456789abcdef01234567'
const rows = [
  { protocol: 'http', ip: '8.8.8.8', port: 8080, url: 'http://8.8.8.8:8080', anonymity: 'elite', https: true, latency_ms: 120, latency_median_ms: 110.5, uptime_24h: 99.5, uptime_7d: 98.2, checks_7d: 72, exit_ip: '8.8.8.8', exit_shared: 1, country: 'us', region: 'A, "quoted"', city: 'Mountain View', timezone: 'America/Los_Angeles', asn: 15169, asn_org: 'Example', sources_count: 3, first_seen: '2026-01-01T00:00:00.000Z', last_checked: '2026-01-02T00:00:00.000Z' },
  { protocol: 'socks5', ip: '1.1.1.1', port: 1080, url: 'socks5://1.1.1.1:1080', anonymity: 'anonymous', https: null, latency_ms: 300, latency_median_ms: null, uptime_24h: 90, uptime_7d: null, checks_7d: 10, exit_ip: null, exit_shared: 1, country: 'de', region: null, city: null, timezone: null, asn: 13335, asn_org: 'Example', sources_count: 1, first_seen: '2026-01-01T00:00:00.000Z', last_checked: '2026-01-02T00:00:00.000Z' },
]
const stats = { generated_at: '2026-01-02T00:00:00.000Z', expires_at: '2026-01-02T00:10:00.000Z', totals: { all: 2, http: 1, socks4: 0, socks5: 1, https: 1, fast: 2, stable: 1, anonymous: 2 }, countries: { de: 1, us: 1 }, countries_count: 2 }

async function sourceFixture(root, override = {}) {
  const source = join(root, 'source'); await mkdir(source)
  await writeFile(join(source, 'all.json'), JSON.stringify(override.rows ?? rows))
  await writeFile(join(source, 'stats.json'), JSON.stringify(override.stats ?? stats))
  await writeFile(join(source, 'LICENSE-DATA'), 'CC0 1.0 Universal\n')
  return source
}

test('prepares isolated Hugging Face, Kaggle dataset, and notebook uploads', async () => {
  const root = await mkdtemp(join(tmpdir(), 'litport-distribution-'))
  try {
    const source = await sourceFixture(root); const output = join(root, 'output')
    const result = prepare({ sourceDir: source, output, owner: 'litportnet', sourceCommit })
    assert.equal(result.rows, 2)
    const card = await readFile(join(output, 'huggingface/README.md'), 'utf8')
    const data = JSON.parse(await readFile(join(output, 'huggingface/all.json'), 'utf8'))
    const csv = await readFile(join(output, 'kaggle-dataset/all.csv'), 'utf8')
    const provenance = JSON.parse(await readFile(join(output, 'kaggle-dataset/provenance.json'), 'utf8'))
    const notebook = JSON.parse(await readFile(join(output, 'kaggle-notebook/analysis.ipynb'), 'utf8'))
    const metadata = JSON.parse(await readFile(join(output, 'kaggle-dataset/dataset-metadata.json'), 'utf8'))
    const kernel = JSON.parse(await readFile(join(output, 'kaggle-notebook/kernel-metadata.json'), 'utf8'))
    assert.deepEqual(data, rows); assert.match(csv, /"A, ""quoted"""/); assert.match(card, /Historical/)
    assert.equal(provenance.source_commit, sourceCommit); assert.equal(provenance.row_count, 2)
    assert.equal(notebook.nbformat, 4); assert.match(notebook.cells[0].source.join(''), /https:\/\/litport\.net\/free-proxy/); assert.match(notebook.cells[0].source.join(''), /https:\/\/litport\.net\/docs\/free-proxy-api/); assert.match(notebook.cells[1].source.join(''), /DATASET_DIR/)
    assert.equal(metadata.id, 'litportnet/free-proxy-observations'); assert.match(metadata.description, /https:\/\/litport\.net\/free-proxy/); assert.deepEqual(metadata.keywords, ['internet'])
    assert.deepEqual(kernel.dataset_sources, ['litportnet/free-proxy-observations']); assert.equal(kernel.enable_internet, 'false')
  } finally { await rm(root, { recursive: true, force: true }) }
})

test('rejects missing, truncated, and inconsistent source files before output changes', async () => {
  const root = await mkdtemp(join(tmpdir(), 'litport-distribution-invalid-'))
  try {
    const source = await sourceFixture(root); const output = join(root, 'output'); await writeFile(join(root, 'sentinel'), 'keep')
    await writeFile(join(source, 'stats.json'), JSON.stringify({ ...stats, truncated: true }))
    assert.throws(() => prepare({ sourceDir: source, output, owner: 'litportnet', sourceCommit }), /truncated/)
    assert.equal(existsSync(output), false)
    await writeFile(join(source, 'stats.json'), JSON.stringify(stats)); await writeFile(join(source, 'all.json'), JSON.stringify([{ ...rows[0], ip: '10.0.0.1', url: 'http://10.0.0.1:8080' }]))
    assert.throws(() => prepare({ sourceDir: source, output, owner: 'litportnet', sourceCommit }), /schema|totals/)
    await rm(join(source, 'stats.json'))
    assert.throws(() => prepare({ sourceDir: source, output, owner: 'litportnet', sourceCommit }), /all.json and stats.json/)
  } finally { await rm(root, { recursive: true, force: true }) }
})

test('refuses an existing output and validates exported invocation arguments', async () => {
  const root = await mkdtemp(join(tmpdir(), 'litport-distribution-existing-'))
  try {
    const source = await sourceFixture(root); const output = join(root, 'output'); await mkdir(output); await writeFile(join(output, 'keep.txt'), 'unchanged')
    assert.throws(() => prepare({ sourceDir: source, output, owner: 'litportnet', sourceCommit }), /must not already exist/)
    assert.equal(await readFile(join(output, 'keep.txt'), 'utf8'), 'unchanged')
    assert.throws(() => prepare({ sourceDir: source, output: join(root, 'new-output'), owner: 'invalid owner', sourceCommit }), /owner/)
    assert.throws(() => prepare({ sourceDir: source, output: join(root, 'new-output'), owner: 'litportnet', sourceCommit: 'not-a-commit' }), /source-commit/)
  } finally { await rm(root, { recursive: true, force: true }) }
})
