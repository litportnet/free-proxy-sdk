#!/usr/bin/env node
// Publish the tested PHP package as a Composer-compatible repository root.
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../packages/php/', import.meta.url));
const version = process.argv[process.argv.indexOf('--version') + 1];
if (!process.argv.includes('--version') || !/^\d+\.\d+\.\d+$/.test(version)) throw new Error('Usage: sync-php-repository.mjs --version X.Y.Z');
const token = process.env.GITHUB_TOKEN;
if (!token) throw new Error('GITHUB_TOKEN with write access to litportnet/free-proxy-php is required (Actions secret PHP_REPOSITORY_TOKEN).');
const repo = 'repos/litportnet/free-proxy-php';
async function api(endpoint, method = 'GET', body, allow404 = false) {
  const response = await fetch(`https://api.github.com/${endpoint}`, {
    method, headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (allow404 && response.status === 404) return null;
  if (!response.ok) throw new Error(`GitHub ${method} ${endpoint}: HTTP ${response.status}`);
  return response.status === 204 ? null : response.json();
}
const composer = JSON.parse(await fs.readFile(path.join(root, 'composer.json'), 'utf8'));
if (composer.name !== 'litportnet/free-proxy-sdk') throw new Error('Unexpected Composer package identity');
const files = [];
async function collect(directory, prefix = '') {
  for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
    if (['vendor', '.git', 'composer.lock'].includes(entry.name)) continue;
    if (entry.isSymbolicLink()) throw new Error('Package must not include symbolic links');
    const name = prefix + entry.name;
    if (entry.isDirectory()) await collect(path.join(directory, entry.name), `${name}/`);
    else files.push({ path: name, mode: '100644', type: 'blob', content: await fs.readFile(path.join(directory, entry.name), 'utf8') });
  }
}
await collect(root);
if (!files.some(f => f.path === 'LICENSE') || !files.some(f => f.path === 'README.md')) throw new Error('Missing package documentation or license');
let info = await api(repo, 'GET', undefined, true);
if (!info) info = await api('orgs/litportnet/repos', 'POST', {
  name: 'free-proxy-php', private: false, auto_init: true,
  description: 'PHP client for Litport free-proxy snapshots. Fetch and filter HTTP, SOCKS4 and SOCKS5 records by country, latency and freshness. Composer package; no API key required.',
  homepage: 'https://litport.net/free-proxy',
});
if (info.private) throw new Error('Expected public PHP repository');
const branch = info.default_branch;
const head = await api(`${repo}/git/ref/heads/${branch}`);
const commit = await api(`${repo}/git/commits/${head.object.sha}`);
// An explicit tree makes the split an exact copy of the package, without stale files.
const tree = await api(`${repo}/git/trees`, 'POST', { tree: files });
const tagPath = `${repo}/git/ref/tags/v${version}`;
const existingTag = await api(tagPath, 'GET', undefined, true);
if (existingTag) {
  let object = existingTag.object;
  if (object.type === 'tag') object = (await api(`${repo}/git/tags/${object.sha}`)).object;
  const tagged = await api(`${repo}/git/commits/${object.sha}`);
  if (tagged.tree.sha !== tree.sha) throw new Error(`Tag v${version} already exists with different contents; increment the package version.`);
  console.log(`Already published: https://github.com/litportnet/free-proxy-php/tree/v${version}`);
} else {
  let sha = head.object.sha;
  if (commit.tree.sha !== tree.sha) {
    const next = await api(`${repo}/git/commits`, 'POST', { message: `Release PHP SDK ${version}`, tree: tree.sha, parents: [sha] });
    await api(`${repo}/git/refs/heads/${branch}`, 'PATCH', { sha: next.sha, force: false });
    sha = next.sha;
  }
  await api(`${repo}/git/refs`, 'POST', { ref: `refs/tags/v${version}`, sha });
  console.log(`Published: https://github.com/litportnet/free-proxy-php/tree/v${version}`);
}
await api(`${repo}/topics`, 'PUT', { names: ['php', 'composer', 'sdk', 'free-proxy', 'free-proxy-list', 'proxy-list', 'http-proxy', 'socks4', 'socks5', 'proxy-api', 'litport'] });
console.log('Packagist submission URL: https://github.com/litportnet/free-proxy-php');
