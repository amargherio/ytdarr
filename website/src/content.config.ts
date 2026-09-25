import { defineCollection } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';
import { z } from 'astro/zod';

export const collections = {
  docs: defineCollection({
    loader: docsLoader({
      generateId: ({ entry }) => entry.replace(/\.md$/, '').replace(/\/index$/, ''),
    }),
    schema: docsSchema({ extend: z.object({ description: z.string().trim().min(1) }) }),
  }),
};
