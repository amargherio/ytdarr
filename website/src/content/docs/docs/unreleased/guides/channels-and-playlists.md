---
title: Channels and playlists
description: Add, monitor, synchronize, inspect, and safely remove YouTube channels and their playlists.
sidebar:
  order: 2
---

A direct channel URL, handle, or ID is the most predictable way to add a channel: it lets you choose add, initial sync, and monitoring deliberately. Search is useful for discovery, but playlist search is not an enabled add mode.

## Add and synchronize a channel

1. Open **Channels → Add Channel** (`/channels/add`).
2. Resolve a direct URL, handle, or ID, then choose the add, sync, and monitor options.
3. Open the channel detail page and verify the saved monitoring state.
4. Refresh metadata or run a sync. Inspect its videos and playlists after the job completes.

A full sync gathers the known metadata; incremental synchronization checks newer material. Monitoring controls future metadata sync, not automatic downloading. Search's **Add Only** and **Add & Sync** path omits `monitor=false` while the handler defaults monitoring to true; handling an already-known search result can update local state without necessarily persisting monitoring. Treat the channel detail page as the source of truth and correct the setting there if necessary.

## Work with playlists

On a channel detail page, inspect discovered playlists and choose whether to monitor them. Playlist and channel sync are metadata operations; they do not place videos in the download queue. Use [downloads and queue](../downloads-and-queue/) to choose individual videos.

## Remove a channel safely

From the **channel list**, **Remove → Keep downloaded files** removes the Ytdarr record but preserves downloaded files. **Remove → Delete downloaded files** asks for confirmation and recursively deletes the stored channel directory; it is irreversible. Back up any media you need before confirming it.

Do not rely on a channel-detail **Delete Files** control: the channel-detail channel/playlist/all-video variants are currently unimplemented stubs. If a removal did not do what you expected, stop issuing delete actions, inspect the channel directory, and use the list-level choice only after confirming its destructive outcome.