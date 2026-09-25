import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { prepareDocs, selectReleaseLines } from '../scripts/prepare-docs.mjs';

const source = 'website/src/content/docs/docs/unreleased';
const git = (root, ...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();
const release = (tag_name, options = {}) => ({ tag_name, draft: false, prerelease: false, ...options });

async function withRepository(callback) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'ytdarr-docs-'));
  const site = path.join(root, 'website');
  try {
    git(root, 'init', '-b', 'main');
    git(root, 'config', 'user.name', 'Documentation Test');
    git(root, 'config', 'user.email', 'docs@example.test');
    await mkdir(path.join(root, source, '_assets'), { recursive: true });
    await callback(root, site);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

async function commit(root, version, text, tag) {
  await writeFile(path.join(root, 'VERSION'), `${version}\n`);
  await writeFile(path.join(root, source, 'index.md'), `---\ntitle: Index\ndescription: ${text}\n---\n\n${text}\n`);
  await writeFile(path.join(root, source, '_assets', 'capture.svg'), `<svg xmlns="http://www.w3.org/2000/svg"><title>${text}</title></svg>`);
  git(root, 'add', '.');
  git(root, 'commit', '-m', text);
  if (tag) git(root, 'tag', tag);
  git(root, 'update-ref', 'refs/remotes/origin/main', 'HEAD');
}

test('retains the highest numeric stable patch in each minor line', () => {
  assert.deepEqual(selectReleaseLines([
    release('v0.1.1'), release('v0.1.2'), release('v0.2.0'), release('v0.10.0'),
    release('v0.9.9'), release('v0.10.1', { prerelease: true }), release('v2.0.0', { draft: true }),
    release('v1.0.0-rc1'),
  ]).map(({ tag }) => tag), ['v0.10.0', 'v0.9.9', 'v0.2.0', 'v0.1.2']);
  assert.deepEqual(selectReleaseLines([]), []);
});

test('copies exact tagged source and keeps other minor lines on patch replacement', async () => {
  await withRepository(async (root, site) => {
    await commit(root, '0.1.1', 'first patch', 'v0.1.1');
    await commit(root, '0.1.2', 'second patch', 'v0.1.2');
    await commit(root, '0.2.0', 'new minor', 'v0.2.0');
    await commit(root, '0.2.1', 'development only');
    const releases = [release('v0.1.1'), release('v0.1.2'), release('v0.2.0'), release('v0.3.0', { draft: true })];
    const result = await prepareDocs({ repoRoot: root, siteRoot: site, releases });
    assert.equal(result.defaultVersion, 'v0.2');
    assert.deepEqual(result.versions.map(({ id }) => id), ['v0.2', 'v0.1', 'unreleased']);
    assert.match(await readFile(path.join(root, 'website/src/content/docs/docs/v0.1/index.md'), 'utf8'), /second patch/);
    assert.match(await readFile(path.join(root, 'website/src/content/docs/docs/v0.1/_assets/capture.svg'), 'utf8'), /second patch/);
    assert.match(await readFile(path.join(root, 'website/src/content/docs/docs/v0.2/index.md'), 'utf8'), /new minor/);
    assert.match(await readFile(path.join(root, source, 'index.md'), 'utf8'), /development only/);
    await commit(root, '0.2.2', 'newer patch', 'v0.2.2');
    await prepareDocs({ repoRoot: root, siteRoot: site, releases: [...releases, release('v0.2.2')] });
    assert.match(await readFile(path.join(root, 'website/src/content/docs/docs/v0.1/index.md'), 'utf8'), /second patch/);
    assert.match(await readFile(path.join(root, 'website/src/content/docs/docs/v0.2/index.md'), 'utf8'), /newer patch/);
  });
});

test('rejects missing or inconsistent released source instead of inventing history', async () => {
  await withRepository(async (root, site) => {
    await commit(root, '0.1.1', 'old tag', 'v0.1.1');
    await assert.rejects(prepareDocs({ repoRoot: root, siteRoot: site, releases: [release('v0.1.2')] }), /v0\.1\.2.*cannot use/);
    git(root, 'tag', 'v0.1.2');
    await assert.rejects(prepareDocs({ repoRoot: root, siteRoot: site, releases: [release('v0.1.2')] }), /v0\.1\.2.*VERSION/);
  });
});
