import { defineRouteMiddleware } from '@astrojs/starlight/route-data';
import manifest from './generated/docs-versions.json';

export const onRequest = defineRouteMiddleware((context) => {
  const route = context.locals.starlightRoute;
  const match = /^docs\/(unreleased|v\d+\.\d+)(?:\/|$)/.exec(route.id);
  if (!match) return;
  const version = manifest.versions.find(({ id }) => id === match[1]);
  if (!version) return;
  route.sidebar = route.sidebar
    .filter((item) => item.label === version.label || item.label.startsWith(`${version.label} · `))
    .map((item) => item.type === 'group' ? { ...item, label: item.label.slice(version.label.length + 3) } : item);
  route.pagination = {
    prev: route.pagination.prev?.href.includes(`/docs/${version.id}/`) ? route.pagination.prev : undefined,
    next: route.pagination.next?.href.includes(`/docs/${version.id}/`) ? route.pagination.next : undefined,
  };
});
