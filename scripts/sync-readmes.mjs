import { readFile, writeFile } from 'node:fs/promises'

const rootReadme = new URL('../README.md', import.meta.url)
const packageReadmes = [
  new URL('../packages/js/README.md', import.meta.url),
  new URL('../packages/python/README.md', import.meta.url),
]
const sharedBlocks = ['intro', 'safety', 'resources']
const staticBanner = '[![Litport free proxies: live lists, API and SDKs](https://raw.githubusercontent.com/litportnet/free-proxy-sdk/main/assets/free-proxy-banner-static.png)](https://litport.net/free-proxy)'

if (process.argv.slice(2).some((argument) => argument !== '--check')) {
  throw new Error('Usage: node scripts/sync-readmes.mjs [--check]')
}

const checkOnly = process.argv.includes('--check')

function marker(name, edge) {
  return `<!-- shared-readme:${name}:${edge} -->`
}

function occurrences(contents, value) {
  let count = 0
  let offset = 0

  while ((offset = contents.indexOf(value, offset)) !== -1) {
    count += 1
    offset += value.length
  }

  return count
}

function markedBlock(contents, name, filePath) {
  const start = marker(name, 'start')
  const end = marker(name, 'end')
  const startCount = occurrences(contents, start)
  const endCount = occurrences(contents, end)

  if (startCount !== 1 || endCount !== 1) {
    throw new Error(`${filePath}: shared-readme:${name} markers must each appear exactly once (found ${startCount} start, ${endCount} end)`)
  }

  const startIndex = contents.indexOf(start)
  const endIndex = contents.indexOf(end)

  if (endIndex < startIndex) {
    throw new Error(`${filePath}: shared-readme:${name} end marker appears before its start marker`)
  }

  const endOffset = endIndex + end.length
  return {
    value: contents.slice(startIndex, endOffset),
    startIndex,
    endOffset,
  }
}

function assertBannerIsFirst(contents, filePath) {
  const bannerBlock = canonicalBlocks.get('banner')
  if (!contents.startsWith(`${bannerBlock}\n\n# `)) {
    throw new Error(`${filePath}: the static free-proxy banner must appear before the title`)
  }
}

const rootContents = await readFile(rootReadme, 'utf8')
const canonicalBlocks = new Map(
  sharedBlocks.map((name) => [name, markedBlock(rootContents, name, rootReadme.pathname).value]),
)
canonicalBlocks.set('banner', `${marker('banner', 'start')}\n${staticBanner}\n${marker('banner', 'end')}`)
const driftedFiles = []

for (const packageReadme of packageReadmes) {
  const original = await readFile(packageReadme, 'utf8')
  let updated = original

  for (const name of ['banner', ...sharedBlocks]) {
    const target = markedBlock(updated, name, packageReadme.pathname)
    updated = `${updated.slice(0, target.startIndex)}${canonicalBlocks.get(name)}${updated.slice(target.endOffset)}`
  }

  assertBannerIsFirst(updated, packageReadme.pathname)

  if (updated !== original) {
    driftedFiles.push(packageReadme.pathname)
    if (!checkOnly) {
      await writeFile(packageReadme, updated)
    }
  }
}

if (driftedFiles.length > 0) {
  const message = `Shared README blocks are out of sync: ${driftedFiles.join(', ')}`
  if (checkOnly) {
    throw new Error(message)
  }
  console.log(`Updated ${driftedFiles.join(', ')}`)
}
