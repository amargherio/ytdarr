---
title: Media library organization
description: Configure writable media roots and present Ytdarr downloads to Jellyfin, Plex, or Emby TV libraries.
sidebar:
  order: 5
---

Before downloading, add an existing writable media root in Settings. A channel's chosen path is persisted; editing roots does not relocate files already written. Multiple active roots have no ordering guarantee, and purpose does not route content automatically.

## Set permissions and a root

1. Create or select a media root that the service can write.
2. If another media service needs the same files, create a shared OS group, add both service users, and restart them so new memberships take effect.
3. Set the media owner group and three-digit file/directory modes in Settings.
4. Use **Apply to existing media** only when you intend to normalize existing files; new writes use the saved policy automatically.

The group must exist and include the running Ytdarr process. Permission normalization skips symlinks and captures the current policy when queued. See [settings reference](../../reference/settings/).

## Read the generated layout

A fictional Workshop Notes upload might be placed as:

```text
/media/Workshop Notes/tvshow.nfo
/media/Workshop Notes/poster.jpg
/media/Workshop Notes/banner.jpg
/media/Workshop Notes/Season 2026/Workshop Notes - S2026E001 - Field Journal.mp4
/media/Workshop Notes/Season 2026/Workshop Notes - S2026E001 - Field Journal.nfo
```

Ytdarr maps channel → show, upload year → season, video → episode. Episode ordering uses upload date and then internal ID, so a later metadata correction can affect numbering. Point a Jellyfin, Plex, or Emby **TV** library at the root and allow it to scan. Matching can require media-server configuration; Ytdarr does not claim a dedicated Plex metadata adapter.

Adding a channel creates its directory and `videos/` subdirectory, downloads its available avatar/thumbnail as `poster.<ext>` and banner as `banner.<ext>`, and writes `tvshow.nfo`. Search-based additions fetch the full channel details first so **Add Only** also includes the banner. The show NFO contains the channel title, description, YouTube ID, URL, and local artwork references with `poster` and `banner` aspects. Extensions follow the downloaded image's content type; files and directories use the configured media group and modes. See [Jellyfin's artwork names](https://jellyfin.org/docs/general/server/media/shows/#metadata-images) and [NFO image handling](https://jellyfin.org/docs/general/server/metadata/nfo/#image-paths-and-urls-in-nfo-files).

Full and incremental channel refreshes check the latest image URLs. ETag and Last-Modified validators are used only for the same URL with an existing local image; changed URLs and missing files trigger a fresh download. Unchanged images are not rewritten. Successful updates replace the disk and web cache artwork, remove obsolete image extensions, and update the show NFO. Existing `avatar.<ext>` caches are migrated to `poster.<ext>` locally. Missing artwork is omitted from the NFO; download or filesystem failures are logged without removing the channel, and subsequent channel refreshes try again.

If the files are missing from a library, first verify the service group's access and its library root, then inspect the canonical path and NFO. Do not expect root edits or quality-profile changes to move existing files.