import manifest from '../generated/docs-versions.json';

const form = document.querySelector<HTMLFormElement>('#docs-search-form')!;
const input = document.querySelector<HTMLInputElement>('#search-query')!;
const versionSelect = document.querySelector<HTMLSelectElement>('#search-version')!;
const searchStatus = document.querySelector<HTMLElement>('#search-status')!;
const results = document.querySelector<HTMLOListElement>('#search-results')!;
const more = document.querySelector<HTMLButtonElement>('#more-results')!;
const recovery = document.querySelector<HTMLElement>('#search-recovery')!;
const known = new Set(manifest.versions.map(({ id }) => id));
let generation = 0;
let current: Array<{ url: string; meta: { title: string }; plain_excerpt: string }> = [];
let visible = 0;
type SearchIndex = {
  search(term: string, options: { filters: { version: string } }): Promise<{
    results: Array<{ data(): Promise<(typeof current)[number]> }>;
  }>;
};
let searchIndex: SearchIndex | undefined;


function createResult(item: (typeof current)[number], version: string): HTMLLIElement {
  const row = document.createElement('li');
  const link = document.createElement('a');
  link.href = item.url;
  link.textContent = item.meta.title;
  const summary = document.createElement('p');
  summary.textContent = `${version} · ${item.plain_excerpt}`;
  row.append(link, summary);
  return row;
}

function showMore(version: string): void {
  const end = Math.min(visible + 10, current.length);
  for (const item of current.slice(visible, end)) results.append(createResult(item, version));
  visible = end;
  more.hidden = visible >= current.length;
  searchStatus.textContent = `${current.length} ${current.length === 1 ? 'result' : 'results'} in ${version}.`;
}

function readQuery(): { query: string; version: string } {
  const params = new URLSearchParams(location.search);
  const value = params.get('version');
  return { query: params.get('q')?.trim() ?? '', version: value && known.has(value) ? value : manifest.defaultVersion };
}

async function search(): Promise<void> {
  const request = ++generation;
  const { query, version } = readQuery();
  input.value = query;
  versionSelect.value = version;
  current = [];
  visible = 0;
  results.replaceChildren();
  more.hidden = true;
  recovery.hidden = true;
  if (!query) {
    searchStatus.textContent = 'Enter search terms to find documentation.';
    return;
  }
  searchStatus.textContent = `Searching ${version}…`;
  try {
    // The generated index does not exist during Vite bundling, so load it from Pages on demand.
    const index: SearchIndex = searchIndex ??= (await import(/* @vite-ignore */ `${import.meta.env.BASE_URL}pagefind/pagefind.js`))
      .createInstance({ basePath: `${import.meta.env.BASE_URL}pagefind/`, noWorker: true });
    const found = await index.search(query, { filters: { version } });
    const data = await Promise.all(found.results.map((result) => result.data()));
    if (request !== generation) return;
    current = data;
    if (current.length) showMore(version);
    else searchStatus.textContent = `No results in ${version}.`;
  } catch (error) {
    searchIndex = undefined;
    console.error('Documentation search failed:', String(error));
    if (request !== generation) return;
    searchStatus.textContent = `Search unavailable for ${version}.`;
    recovery.hidden = false;
    recovery.querySelector('a')!.href = `${import.meta.env.BASE_URL}docs/${version}/`;
  }
}

form.addEventListener('submit', (event) => {
  event.preventDefault();
  const params = new URLSearchParams({ q: input.value.trim(), version: versionSelect.value });
  history.pushState(null, '', `${form.action}?${params}`);
  void search();
});
more.addEventListener('click', () => showMore(versionSelect.value));
window.addEventListener('popstate', () => { void search(); });
void search();
