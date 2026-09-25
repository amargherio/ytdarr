import { build } from 'esbuild';

await build({
  entryPoints: ['src/scripts/search.ts'],
  outfile: 'public/search.js',
  bundle: true,
  format: 'esm',
  platform: 'browser',
  target: 'es2022',
  define: { 'import.meta.env.BASE_URL': '"/ytdarr/"' },
});
