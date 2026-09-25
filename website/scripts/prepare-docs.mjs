import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const siteRoot = fileURLToPath(new URL('..', import.meta.url));
const repoRoot = path.resolve(siteRoot, '..');
const sourceDirectory = 'website/src/content/docs/docs/unreleased';
const releasePattern = /^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;

function git(root, ...args) {
  return execFileSync('git', args, { cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'] }).trimEnd();
}

export function selectReleaseLines(releases) {
  if (!Array.isArray(releases)) throw new TypeError('GitHub releases must be an array');
  const lines = new Map();
  for (const release of releases) {
    if (release.draft || release.prerelease) continue;
    const match = releasePattern.exec(release.tag_name);
    if (!match) continue;
    const [, major, minor, patch] = match.map((value, index) => index === 0 ? value : Number(value));
    const key = `${major}.${minor}`;
    const previous = lines.get(key);
    if (!previous || patch > previous.patch) lines.set(key, { major, minor, patch, tag: release.tag_name });
  }
  return [...lines.values()].sort((a, b) => b.major - a.major || b.minor - a.minor || b.patch - a.patch);
}

function taggedFiles(root, tag) {
  const tree = git(root, 'ls-tree', '-r', '-z', tag, '--', sourceDirectory);
  const prefix = `${sourceDirectory}/`;
  const files = [];
  for (const record of tree.split('\0')) {
    if (!record) continue;
    const separator = record.indexOf('\t');
    const [mode, type] = record.slice(0, separator).split(' ');
    const source = record.slice(separator + 1);
    const relative = source.slice(prefix.length);
    if (!source.startsWith(prefix) || relative.split('/').some((part) => part === '..' || part === '.' || !part)) {
      throw new Error(`${tag}: invalid documentation path ${source}`);
    }
    if (mode !== '100644' && mode !== '100755') throw new Error(`${tag}: symlink or unsupported file ${source}`);
    if (type !== 'blob') throw new Error(`${tag}: unsupported documentation entry ${source}`);
    if (!relative.endsWith('.md') && !/^_assets\/.*\.(avif|webp|png|jpe?g|svg)$/i.test(relative)) {
      throw new Error(`${tag}: unsupported documentation file ${source}`);
    }
    files.push({ source, relative });
  }
  if (!files.some((file) => file.relative === 'index.md')) {
    throw new Error(`${tag}: missing ${sourceDirectory}/index.md`);
  }
  return files;
}

export async function prepareDocs({ repoRoot: root, siteRoot: site, releases }) {
  const selected = selectReleaseLines(releases);
  const docs = path.join(site, 'src/content/docs/docs');
  if (!existsSync(path.join(docs, 'unreleased/index.md'))) throw new Error('Missing current documentation index.md');

  // Validate every release before touching the previously generated archives.
  const archives = selected.map(({ major, minor, patch, tag }) => {
    try {
      const commit = git(root, 'rev-parse', '--verify', `refs/tags/${tag}^{commit}`);
      if (git(root, 'show', `${commit}:VERSION`) !== `${major}.${minor}.${patch}`) {
        throw new Error('VERSION does not match the published release tag');
      }
      execFileSync('git', ['merge-base', '--is-ancestor', commit, 'origin/main'], { cwd: root });
      return { id: `v${major}.${minor}`, tag, commit, files: taggedFiles(root, commit) };
    } catch (error) {
      throw new Error(`${tag}: cannot use published release docs: ${error.message}`, { cause: error });
    }
  });

  for (const { id } of archives) await rm(path.join(docs, id), { recursive: true, force: true });
  // Also remove generated archives whose release line is no longer published.
  for (const directory of await readdir(docs, { withFileTypes: true })) {
    if (directory.isDirectory() && /^v\d+\.\d+$/.test(directory.name) && !archives.some(({ id }) => id === directory.name)) {
      await rm(path.join(docs, directory.name), { recursive: true, force: true });
    }
  }
  for (const { id, commit, files } of archives) {
    for (const { source, relative } of files) {
      const destination = path.join(docs, id, relative);
      await mkdir(path.dirname(destination), { recursive: true });
      const bytes = execFileSync('git', ['show', `${commit}:${source}`], { cwd: root, maxBuffer: 16 * 1024 * 1024 });
      await writeFile(destination, bytes);
    }
  }
  const versions = [
    ...archives.map(({ id, tag, commit }) => ({ id, label: `${id} (${tag})`, tag, sourceRef: commit })),
    { id: 'unreleased', label: 'Unreleased', tag: null, sourceRef: 'main' },
  ];
  const manifest = { defaultVersion: archives[0]?.id ?? 'unreleased', versions };
  const generated = path.join(site, 'src/generated');
  await mkdir(generated, { recursive: true });
  await writeFile(path.join(generated, 'docs-versions.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  return manifest;
}

async function publishedReleases() {
  const releases = [];
  let url = 'https://api.github.com/repos/amargherio/ytdarr/releases?per_page=100';
  while (url) {
    const response = await fetch(url, {
      headers: {
        Accept: 'application/vnd.github+json',
        'User-Agent': 'ytdarr-website-build',
        ...(process.env.GH_TOKEN ? { Authorization: `Bearer ${process.env.GH_TOKEN}` } : {}),
      },
    });
    if (!response.ok) throw new Error(`GitHub releases request failed: HTTP ${response.status} ${url}`);
    const page = await response.json();
    if (!Array.isArray(page)) throw new Error('GitHub releases response was not an array');
    releases.push(...page);
    const next = response.headers.get('link')?.split(',').find((link) => /rel="next"/.test(link));
    url = next?.match(/<([^>]+)>/)?.[1] ?? '';
  }
  return releases;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args.length && (args.length !== 2 || args[0] !== '--releases-file')) {
    throw new Error('Usage: node scripts/prepare-docs.mjs [--releases-file FILE]');
  }
  const releases = args.length ? JSON.parse(await readFile(args[1], 'utf8')) : await publishedReleases();
  const manifest = await prepareDocs({ repoRoot, siteRoot, releases });
  console.log(`Documentation: ${manifest.versions.map(({ label }) => label).join(', ')}`);
}
