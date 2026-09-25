import { existsSync } from 'node:fs';
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import tailwindcss from '@tailwindcss/vite';
import manifest from './src/generated/docs-versions.json' with { type: 'json' };

const sections = ['installation', 'guides', 'operations', 'reference', 'development'];

export default defineConfig({
  site: 'https://amargherio.github.io',
  base: '/ytdarr',
  output: 'static',
  trailingSlash: 'always',
  vite: { plugins: [tailwindcss()], build: { modulePreload: false } },
  integrations: [
    starlight({
      title: 'Ytdarr',
      description: 'Self-hosted YouTube channel monitoring and downloads for your media library.',
      defaultLocale: 'en',
      disable404Route: true,
      customCss: ['./src/styles/site.css'],
      routeMiddleware: './src/route-data.ts',
      expressiveCode: { frames: { showCopyToClipboardButton: false } },
      head: [{ tag: 'script', attrs: { src: '/ytdarr/copy.js', defer: true } }],
      components: {
        Header: './src/components/SiteHeader.astro',
        PageTitle: './src/components/ArticleTitle.astro',
        ThemeProvider: './src/components/SiteThemeProvider.astro',
        ThemeSelect: './src/components/SiteThemeSelect.astro',
      },
      sidebar: manifest.versions.flatMap(({ id, label }) => [
        { label, slug: `docs/${id}` },
        { label: `${label} · Start here`, items: [{ slug: `docs/${id}/getting-started` }] },
        ...sections
          .filter((section) => existsSync(new URL(`./src/content/docs/docs/${id}/${section}`, import.meta.url)))
          .map((section) => ({
            label: `${label} · ${section[0].toUpperCase()}${section.slice(1)}`,
            items: [{ autogenerate: { directory: `docs/${id}/${section}` } }],
          })),
      ]),
      social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/amargherio/ytdarr' }],
    }),
  ],
});
