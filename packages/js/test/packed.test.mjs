import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { createRequire } from 'node:module'
import { join } from 'node:path'
import test from 'node:test'
import { pathToFileURL } from 'node:url'

test('the npm tarball exposes working CommonJS and ESM entry points', async () => {
  const temp = await mkdtemp(join(tmpdir(), 'litportnet-free-proxy-sdk-'))
  try {
    execFileSync('npm', ['pack', '--pack-destination', temp], { cwd: new URL('..', import.meta.url), stdio: 'pipe' })
    const tarball = join(temp, 'litportnet-free-proxy-sdk-0.0.0.tgz')
    execFileSync('tar', ['-xzf', tarball, '-C', temp], { stdio: 'pipe' })
    const packageRoot = join(temp, 'package')
    const cjs = createRequire(join(packageRoot, 'package.json'))('./dist/index.cjs')
    const esm = await import(pathToFileURL(join(packageRoot, 'dist/index.js')).href)
    assert.equal(typeof cjs.Client, 'function')
    assert.equal(typeof esm.Client, 'function')
  } finally { await rm(temp, { recursive: true, force: true }) }
})
