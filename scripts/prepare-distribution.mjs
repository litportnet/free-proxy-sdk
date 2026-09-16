#!/usr/bin/env node
import { createHash } from 'node:crypto'
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { join, resolve, relative } from 'node:path'

export const FIELDS = ['protocol', 'ip', 'port', 'url', 'anonymity', 'https', 'latency_ms', 'latency_median_ms', 'uptime_24h', 'uptime_7d', 'checks_7d', 'exit_ip', 'exit_shared', 'country', 'region', 'city', 'timezone', 'asn', 'asn_org', 'sources_count', 'first_seen', 'last_checked']
const PROTOCOLS = new Set(['http', 'socks4', 'socks5'])
const ANONYMITY = new Set(['transparent', 'anonymous', 'elite', 'unknown'])
const cc0Fallback = 'Creative Commons CC0 1.0 Universal\n\nTo the extent possible under law, Litport has waived all copyright and related rights to this dataset. https://creativecommons.org/publicdomain/zero/1.0/\n'

const usage = 'node scripts/prepare-distribution.mjs --source-dir <downloaded-data-dir> --output <output-dir> --owner litportnet --source-commit <40-hex> [--license-data <path>]'
const parseArgs = argv => {
  const args = {}
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index]
    if (!['--source-dir', '--output', '--owner', '--source-commit', '--license-data'].includes(key)) throw new Error(`Unknown argument: ${key}\n${usage}`)
    const value = argv[++index]
    if (!value) throw new Error(`Missing value for ${key}\n${usage}`)
    args[key.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = value
  }
  for (const key of ['sourceDir', 'output', 'owner', 'sourceCommit']) if (!args[key]) throw new Error(`--${key.replace(/[A-Z]/g, letter => `-${letter.toLowerCase()}`)} is required\n${usage}`)
  if (!/^[0-9a-f]{40}$/i.test(args.sourceCommit)) throw new Error('--source-commit must be exactly 40 hexadecimal characters')
  if (!/^[a-z0-9][a-z0-9-]*$/i.test(args.owner)) throw new Error('--owner is malformed')
  return args
}
const json = (path, label) => { try { return JSON.parse(readFileSync(path, 'utf8')) } catch (error) { throw new Error(`Malformed ${label}: ${error.message}`) } }
const sha256 = value => createHash('sha256').update(value).digest('hex')
const iso = value => typeof value === 'string' && Number.isFinite(new Date(value).getTime()) && /(?:Z|[+-]\d\d:\d\d)$/.test(value)
const publicIpv4 = ip => {
  const parts = typeof ip === 'string' ? ip.split('.') : []
  if (parts.length !== 4 || parts.some(part => !/^\d+$/.test(part) || Number(part) > 255)) return false
  const value = parts.map(Number).reduce((total, part) => total * 256 + part, 0)
  const ranges = [[0x00000000, 8], [0x0a000000, 8], [0x64400000, 10], [0x7f000000, 8], [0xa9fe0000, 16], [0xac100000, 12], [0xc0000000, 24], [0xc0000200, 24], [0xc0a80000, 16], [0xc6120000, 15], [0xc6336400, 24], [0xcb007100, 24], [0xe0000000, 4], [0xf0000000, 4]]
  return !ranges.some(([network, prefix]) => Math.floor(value / 2 ** (32 - prefix)) === Math.floor(network / 2 ** (32 - prefix)))
}
const csvCell = value => {
  if (value == null) return ''
  const text = String(value)
  return /[",\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text
}
const csv = rows => `${FIELDS.join(',')}\r\n${rows.map(row => FIELDS.map(field => csvCell(row[field])).join(',')).join('\r\n')}\r\n`
const totalsFor = rows => ({
  all: rows.length,
  http: rows.filter(row => row.protocol === 'http').length,
  socks4: rows.filter(row => row.protocol === 'socks4').length,
  socks5: rows.filter(row => row.protocol === 'socks5').length,
  https: rows.filter(row => row.https === true).length,
  fast: rows.filter(row => row.latency_ms < 1000).length,
  stable: rows.filter(row => row.uptime_7d != null && row.uptime_7d >= 90 && row.checks_7d >= 50).length,
  anonymous: rows.filter(row => row.anonymity === 'anonymous' || row.anonymity === 'elite').length,
})
const countriesFor = rows => Object.fromEntries([...new Set(rows.map(row => row.country).filter(Boolean))].sort().map(country => [country, rows.filter(row => row.country === country).length]))
const sizeCategory = count => count < 1_000 ? 'n<1K' : count < 10_000 ? '1K<n<10K' : count < 100_000 ? '10K<n<100K' : count < 1_000_000 ? '100K<n<1M' : count < 10_000_000 ? '1M<n<10M' : count < 100_000_000 ? '10M<n<100M' : count < 1_000_000_000 ? '100M<n<1B' : 'n>1B'

export function validateSource({ rows, stats }) {
  if (!Array.isArray(rows) || rows.length === 0) throw new Error('all.json must be a non-empty array')
  if (!stats || typeof stats !== 'object' || Array.isArray(stats) || stats.truncated === true) throw new Error('stats.json is missing, malformed, or marked truncated')
  if (!iso(stats.generated_at)) throw new Error('stats.json generated_at must be an ISO timestamp')
  if (stats.expires_at != null && !iso(stats.expires_at)) throw new Error('stats.json expires_at must be an ISO timestamp')
  for (const [index, row] of rows.entries()) {
    if (!row || typeof row !== 'object' || Array.isArray(row)) throw new Error(`row ${index} is malformed`)
    if (FIELDS.some(field => !(field in row))) throw new Error(`row ${index} is missing a schema field`)
    if (!PROTOCOLS.has(row.protocol) || !ANONYMITY.has(row.anonymity) || !publicIpv4(row.ip) || !Number.isInteger(row.port) || row.port < 1 || row.port > 65535 || row.url !== `${row.protocol}://${row.ip}:${row.port}` || !iso(row.first_seen) || !iso(row.last_checked)) throw new Error(`row ${index} violates the public proxy schema`)
  }
  const totals = totalsFor(rows); const countries = countriesFor(rows)
  if (!stats.totals || Object.entries(totals).some(([key, value]) => stats.totals[key] !== value)) throw new Error('stats.json totals are inconsistent with all.json')
  if (stats.countries_count !== Object.keys(countries).length || !stats.countries || Object.entries(countries).some(([key, value]) => stats.countries[key] !== value)) throw new Error('stats.json countries are inconsistent with all.json')
}

const datasetCard = ({ sourceCommit, observedAt, count }) => `---
license: cc0-1.0
pretty_name: Litport free proxy observations
tags:
- networking
- proxies
- http
- socks5
- internet
size_categories:
- ${sizeCategory(count)}
---

# Historical Litport free proxy observations

This is a fixed historical snapshot observed at **${observedAt}**, containing ${count} publicly listed proxy observations. It is not a live feed and carries no freshness badge.

## Data

- all.json and all.csv contain the same public schema fields.
- schema.json records field names, types, and nullability.
- provenance.json records the source commit and SHA-256 checksums.

Source: [litportnet/free-proxy-list](https://github.com/litportnet/free-proxy-list) commit ${sourceCommit}. See the [free proxy page](https://litport.net/free-proxy) and [API documentation](https://litport.net/docs/free-proxy-api).

## Testing only

Free proxies are for testing only. Never send credentials, API keys, cookies, personal data, payment data, or production traffic through them. For real workloads, use [Litport proxies](https://litport.net).
`
const schema = { title: 'Litport free proxy observation', fields: FIELDS.map(name => ({ name, type: ['port', 'latency_ms', 'checks_7d', 'exit_shared', 'asn', 'sources_count'].includes(name) ? 'integer' : ['latency_median_ms', 'uptime_24h', 'uptime_7d'].includes(name) ? 'number' : name === 'https' ? 'boolean' : 'string', nullable: ['https', 'latency_median_ms', 'uptime_7d', 'exit_ip', 'country', 'region', 'city', 'timezone', 'asn', 'asn_org'].includes(name) })) }
const notebook = observedAt => ({
  cells: [
    { cell_type: 'markdown', metadata: {}, source: [`# Historical Litport free proxy observations\n`, `Observation time: **${observedAt}**. This notebook analyzes the mounted [historical Kaggle dataset](https://www.kaggle.com/datasets/litportnet/free-proxy-observations) directly; it does not use SDK freshness filtering.\n`, `Browse the [Litport free proxy list](https://litport.net/free-proxy) and [free-proxy API documentation](https://litport.net/docs/free-proxy-api). The dataset originates from [litportnet/free-proxy-list](https://github.com/litportnet/free-proxy-list).\n`, `Free proxies are for testing only. Never use them for credentials, personal data, payment data, or production traffic.\n`] },
    { cell_type: 'code', execution_count: null, metadata: {}, outputs: [], source: ["from pathlib import Path\n", "import os\n", "import pandas as pd\n", "import matplotlib.pyplot as plt\n", "roots = [Path(os.environ['DATASET_DIR'])] if os.environ.get('DATASET_DIR') else []\n", "roots += [Path('/kaggle/input'), Path('.')]\n", "candidates = [root / 'all.csv' for root in roots] + [path for root in roots if root.exists() for path in root.rglob('all.csv')]\n", "csv_path = next((path for path in candidates if path.exists()), None)\n", "if csv_path is None: raise FileNotFoundError('Set DATASET_DIR or mount a dataset containing all.csv')\n", "df = pd.read_csv(csv_path)\n", "df.head()\n"] },
    { cell_type: 'code', execution_count: null, metadata: {}, outputs: [], source: ["df['protocol'].value_counts().sort_index().plot.bar(title='Observations by protocol')\n", "plt.ylabel('observations')\n", "plt.show()\n", "df['country'].fillna('unknown').value_counts().head(20).plot.bar(title='Top countries')\n", "plt.ylabel('observations')\n", "plt.show()\n", "df['latency_ms'].dropna().plot.hist(bins=40, title='Last-check latency (ms)')\n", "plt.xlabel('milliseconds')\n", "plt.show()\n"] },
  ], metadata: { kernelspec: { display_name: 'Python 3', language: 'python', name: 'python3' }, language_info: { name: 'python', version: '3' } }, nbformat: 4, nbformat_minor: 5,
})

const write = (root, path, content) => { const target = join(root, path); mkdirSync(resolve(target, '..'), { recursive: true }); writeFileSync(target, content) }
export function prepare({ sourceDir, output, owner, sourceCommit, licenseData }) {
  if (!/^[0-9a-f]{40}$/i.test(sourceCommit || '')) throw new Error('--source-commit must be exactly 40 hexadecimal characters')
  if (!/^[a-z0-9][a-z0-9-]*$/i.test(owner || '')) throw new Error('--owner is malformed')
  const source = resolve(sourceDir); const outputDir = resolve(output)
  const allPath = join(source, 'all.json'); const statsPath = join(source, 'stats.json')
  if (!existsSync(allPath) || !existsSync(statsPath)) throw new Error('--source-dir must contain all.json and stats.json')
  const allText = readFileSync(allPath, 'utf8'); const statsText = readFileSync(statsPath, 'utf8')
  const rows = json(allPath, 'all.json'); const stats = json(statsPath, 'stats.json')
  validateSource({ rows, stats })
  if (relative(source, outputDir) === '' || relative(outputDir, source) === '') throw new Error('--output must not equal --source-dir')
  if (existsSync(outputDir)) throw new Error('--output must not already exist')
  const observedAt = new Date(stats.generated_at).toISOString(); const sourceLicense = licenseData || join(source, 'LICENSE-DATA'); const license = existsSync(sourceLicense) ? readFileSync(sourceLicense, 'utf8') : cc0Fallback
  const allJsonSha256 = sha256(allText)
  const provenance = { source_repository: 'https://github.com/litportnet/free-proxy-list', source_commit: sourceCommit.toLowerCase(), source_sha256: allJsonSha256, observed_at: observedAt, row_count: rows.length, all_json_sha256: allJsonSha256, stats_json_sha256: sha256(statsText), license: 'CC0-1.0', snapshot_kind: 'historical' }
  const shared = { 'all.json': `${JSON.stringify(rows, null, 2)}\n`, 'all.csv': csv(rows), 'schema.json': `${JSON.stringify(schema, null, 2)}\n`, 'LICENSE': license, 'provenance.json': `${JSON.stringify(provenance, null, 2)}\n` }
  const datasetReadme = datasetCard({ sourceCommit, observedAt, count: rows.length })
  const kaggleMetadata = { id: `${owner}/free-proxy-observations`, title: 'Litport free proxy observations', subtitle: 'Historical public proxy observations', description: `Historical snapshot observed at ${observedAt}. This is not a live feed. Browse the [Litport free proxy list](https://litport.net/free-proxy) and read the [free-proxy API documentation](https://litport.net/docs/free-proxy-api). Testing only: never send credentials, personal data, payment data, or production traffic through free proxies.`, licenses: [{ name: 'CC0-1.0' }], keywords: ['internet'] }
  const kernelMetadata = { id: `${owner}/free-proxy-observations-analysis`, title: 'Free proxy observations analysis', code_file: 'analysis.ipynb', language: 'python', kernel_type: 'notebook', is_private: 'false', enable_gpu: 'false', enable_internet: 'false', dataset_sources: [`${owner}/free-proxy-observations`], keywords: ['data-analysis'] }
  // Every input is parsed and validated before this first output mutation.
  mkdirSync(outputDir, { recursive: true })
  for (const folder of ['huggingface', 'kaggle-dataset']) for (const [path, content] of Object.entries(shared)) write(outputDir, join(folder, path), content)
  write(outputDir, 'huggingface/README.md', datasetReadme)
  write(outputDir, 'kaggle-dataset/README.md', datasetReadme)
  write(outputDir, 'kaggle-dataset/dataset-metadata.json', `${JSON.stringify(kaggleMetadata, null, 2)}\n`)
  write(outputDir, 'kaggle-notebook/analysis.ipynb', `${JSON.stringify(notebook(observedAt), null, 2)}\n`)
  write(outputDir, 'kaggle-notebook/kernel-metadata.json', `${JSON.stringify(kernelMetadata, null, 2)}\n`)
  return { rows: rows.length, observedAt, output: outputDir, provenance }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try { const result = prepare(parseArgs(process.argv.slice(2))); console.log(`prepared ${result.rows} historical rows observed at ${result.observedAt} in ${result.output}`) } catch (error) { console.error(error.message); process.exitCode = 1 }
}
