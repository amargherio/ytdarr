# Product

## Register

product

## Users

Home media enthusiasts running a Jellyfin or Plex instance who want local access to YouTube videos. They manage their library through Ytdarr or directly through their media app of choice. These are technically capable users comfortable with self-hosted software, but they value tools that stay out of the way and let them accomplish tasks quickly. They check in occasionally to add channels, review new content, and manage their download queue.

## Product Purpose

Ytdarr is a self-hosted YouTube channel monitor and video downloader that organizes content for Jellyfin, Plex, and Emby. It bridges the gap between YouTube and local media libraries by automating channel tracking, video discovery, and downloads through yt-dlp. Success means the user spends minimal time in the UI: add a channel, configure preferences, and trust the system to handle the rest.

## Brand Personality

**Snappy, capable, intuitive.** Ytdarr feels fast and responsive. It communicates system state clearly without overwhelming the user. Controls are where you expect them. The interface earns trust through reliability and directness, not through flashy visuals or unnecessary complexity.

## Anti-references

- **Not a YouTube clone.** Ytdarr is a management tool, not a viewing platform. No algorithmic recommendations, no engagement-driven layouts, no autoplay, no social features.
- **Not a direct Sonarr clone.** While Sonarr inspires the media management paradigm, Ytdarr should have its own visual identity. It borrows the mental model (channels as series, videos as episodes) without copying the UI wholesale.
- **Not a generic SaaS template.** No hero metric dashboards, no gradient accent cards, no identical card grids with icons. The interface should feel purpose-built for this specific task, not assembled from a component library demo.

## Design Principles

1. **State over chrome.** The most important thing on any screen is system state: what's monitored, what's downloading, what needs attention. Visual treatment serves status communication first.
2. **Automate, then get out of the way.** The best session is a short session. Design for quick check-ins and fast task completion, not extended browsing.
3. **Honest feedback.** Progress bars, status badges, and queue counts should always reflect real state. Never hide errors or ambiguity behind optimistic UI.
4. **Familiar patterns, fresh execution.** Borrow proven interaction patterns from the *arr ecosystem (Sonarr, Radarr) but execute them with a distinct visual voice.
5. **Density without clutter.** Show enough information to make decisions without drilling down, but never crowd the screen. Tables and lists earn their density through clear hierarchy and whitespace rhythm.

## Accessibility & Inclusion

- WCAG AA compliance for color contrast in both light and dark themes.
- Respect `prefers-reduced-motion`: disable animations and transitions for users who request it.
- Keyboard navigable: all interactive elements reachable and operable via keyboard.
- Meaningful alt text for channel thumbnails and video images.
- Status communicated through icon + text, never color alone.
