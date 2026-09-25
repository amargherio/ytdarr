const base = import.meta.env.BASE_URL.replace(/\/$/, '');

export function withBase(path: string): string {
  if (!path.startsWith('/') || path.startsWith('//')) throw new Error(`Expected a site-relative path: ${path}`);
  if (path === base || path.startsWith(`${base}/`)) return path;
  return `${base}${path}`;
}

export function docsHref(version: string, topic = ''): string {
  return withBase(`/docs/${version}/${topic ? `${topic.replace(/^\/+|\/+$/g, '')}/` : ''}`);
}
