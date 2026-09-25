---
title: Website authoring
description: Author, preview, search, and release-version the static Ytdarr documentation website.
sidebar:
  order: 4
---

The static site has its own npm project in `website/`. Install and run it there:

```sh
cd website
npm ci
npm run dev
npm run build
npm run preview
npm run verify:site
```

## Author a page

Current content belongs in `website/src/content/docs/docs/unreleased/`. Every Markdown article needs a title, nonempty description, and `sidebar.order`. Use browser-relative directory links such as `../guides/` or `./reference/`, not a hard-coded documentation version, `/docs`, or site base. Put documentation images in the version's `_assets/` subtree and use relative references. Screenshots must contain no personal data, credentials, or third-party artwork and need nearby explanatory text plus useful alt text.

## Preview and search

`npm run dev` prepares the version catalog before Astro watches current-source changes. `npm run build` produces the static site and its Pagefind index; `npm run verify:site` audits the built routes, local links, assets, and accessibility expectations. Search is an enhancement: keep every article reachable with ordinary links and without JavaScript.

## Release archives

The preparation script paginates GitHub release metadata, excludes drafts/prereleases, selects the greatest numeric patch from each stable minor line, and verifies each selected tag's `VERSION`, commit, ancestry, and tagged Unreleased documentation tree. It copies only Markdown and colocated `_assets/` files from that tag into a generated archived version.

Normal deployments never snapshot arbitrary `main`. This makes a released documentation version reconstructible from its source commit and keeps a later patch from erasing other minor lines. The build needs full history and tags; an invalid or missing release document tree fails the build rather than publishing substituted current content.