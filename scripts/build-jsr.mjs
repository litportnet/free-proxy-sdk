import { readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const root = resolve(new URL('..', import.meta.url).pathname)
const sourcePath = resolve(root, 'packages/js/src/index.cjs')
const fieldsPath = resolve(root, 'packages/js/src/fields.generated.js')
const typesPath = resolve(root, 'packages/js/src/index.d.ts')
const outputPath = resolve(root, 'packages/jsr/mod.js')
const outputFieldsPath = resolve(root, 'packages/jsr/fields.generated.js')
const outputTypesPath = resolve(root, 'packages/jsr/mod.d.ts')

const source = await readFile(sourcePath, 'utf8')
const fields = await readFile(fieldsPath, 'utf8')
const types = await readFile(typesPath, 'utf8')

const replaceExactlyOnce = (input, needle, replacement, name) => {
  const first = input.indexOf(needle)
  if (first === -1 || input.indexOf(needle, first + needle.length) !== -1) throw new Error(`Unexpected canonical source: expected exactly one ${name}`)
  return `${input.slice(0, first)}${replacement}${input.slice(first + needle.length)}`
}

let esm = source
esm = replaceExactlyOnce(esm, "'use strict'\n\n", '', 'strict-mode preamble')
esm = replaceExactlyOnce(esm, "const FIELDS = require('./fields.generated.cjs')", "import { FIELDS } from './fields.generated.js'", 'field mapping require')
const exportsLine = "module.exports = { Client, FreeProxyError, TimeoutError, HttpError, NotModifiedWithoutCacheError, SnapshotValidationError, SnapshotTruncatedError, FilterValidationError, getProxies, pickBest, rotate, toProxyUrl, withProxyAgent, DEFAULT_API_URL, DEFAULT_GITHUB_URL }"
esm = replaceExactlyOnce(esm, exportsLine, "export { Client, FreeProxyError, TimeoutError, HttpError, NotModifiedWithoutCacheError, SnapshotValidationError, SnapshotTruncatedError, FilterValidationError, getProxies, pickBest, rotate, toProxyUrl, withProxyAgent, DEFAULT_API_URL, DEFAULT_GITHUB_URL }", 'CommonJS export')
esm = `/* @ts-self-types="./mod.d.ts" */\n// Generated from packages/js/src/index.cjs by scripts/build-jsr.mjs. Do not edit.\n${esm}`

for (const [name, content] of [['mod.js', esm], ['fields.generated.js', fields], ['mod.d.ts', types]]) {
  if (/\brequire\s*\(|\bmodule\.exports\b|\bexports\./.test(content)) throw new Error(`Refusing to publish CommonJS syntax in ${name}`)
}

const outputs = [[outputPath, esm], [outputFieldsPath, fields], [outputTypesPath, types]]
const check = process.argv.includes('--check')
let stale = false
for (const [path, content] of outputs) {
  let current = ''
  try { current = await readFile(path, 'utf8') } catch {}
  if (current !== content) {
    stale = true
    if (!check) await writeFile(path, content)
  }
}
if (check && stale) {
  console.error('JSR artifacts are stale; run node scripts/build-jsr.mjs')
  process.exitCode = 1
}
