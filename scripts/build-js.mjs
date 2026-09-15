import { cp, mkdir, readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'
const root = resolve(new URL('..', import.meta.url).pathname)
const src = resolve(root, 'packages/js/src'), dist = resolve(root, 'packages/js/dist')
await mkdir(dist, { recursive: true })
await cp(resolve(src, 'index.cjs'), resolve(dist, 'index.cjs'))
await cp(resolve(src, 'fields.generated.cjs'), resolve(dist, 'fields.generated.cjs'))
await cp(resolve(src, 'cli.cjs'), resolve(dist, 'cli.cjs'))
await cp(resolve(src, 'index.d.ts'), resolve(dist, 'index.d.ts'))
await writeFile(resolve(dist, 'index.js'), "import sdk from './index.cjs'\nexport default sdk\nexport const { Client, FreeProxyError, TimeoutError, HttpError, NotModifiedWithoutCacheError, SnapshotValidationError, SnapshotTruncatedError, FilterValidationError, getProxies, pickBest, rotate, toProxyUrl, withProxyAgent, DEFAULT_API_URL, DEFAULT_GITHUB_URL } = sdk\n")
