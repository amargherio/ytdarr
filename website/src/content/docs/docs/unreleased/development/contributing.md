---
title: Contributing
description: Make focused, tested, accessible Ytdarr changes using the repository's existing Elixir workflow.
sidebar:
  order: 3
---

Start with [development setup](./). Read the repository's product and design guidance before changing a user surface. Ytdarr aims for direct, stateful, keyboard-usable operation; status must not rely on color alone and user-facing changes should preserve accessibility.

## Make a focused change

1. Find the owning area: LiveViews and components live in `lib/ytdarr_web`, application domains in `lib/ytdarr`, workers in `lib/ytdarr/oban_workers`, and tests under `test/`.
2. Use isolated fixtures and local test data. Do not make tests depend on a live YouTube account, provider quota, or personal media.
3. Add behavior-level coverage for a changed contract, then run the appropriate Mix tests and repository quality workflow.
4. Describe the observable bug or change and reproduction steps in a GitHub issue or pull request.

The current source `VERSION` is `0.1.1-2`; a stable release workflow expects a numeric `vX.Y.Z` tag. The mismatch is factual, not a reason to silently rewrite either value to make documentation or packaging claims easier.

No license or extension API is declared here. Do not invent either in code, docs, or issue templates. Contributors changing the static site should also follow [website authoring](../website/).