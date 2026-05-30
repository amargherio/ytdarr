---
name: Ytdarr
description: Self-hosted YouTube channel monitor and video downloader for Jellyfin, Plex, and Emby
colors:
  signal-red: "oklch(57% 0.24 27.33)"
  bright-signal: "oklch(62% 0.25 27.33)"
  deep-signal: "oklch(52% 0.24 27.33)"
  console-slate: "oklch(55% 0.02 260)"
  charcoal-steel: "oklch(30% 0.01 260)"
  deep-console: "oklch(21% 0.006 285.885)"
  panel-dark: "oklch(17.5% 0.005 285.885)"
  console-floor: "oklch(14.5% 0.004 285.885)"
  console-text: "oklch(96% 0.002 286.375)"
  console-white: "oklch(99% 0 0)"
  panel-light: "oklch(96.5% 0.002 286.375)"
  console-edge: "oklch(92% 0.004 286.32)"
  queue-blue: "oklch(62% 0.19 240)"
  complete-green: "oklch(64% 0.15 160)"
  caution-amber: "oklch(72% 0.17 70)"
  fault-red: "oklch(58% 0.24 27)"
typography:
  display:
    fontFamily: "ui-sans-serif, system-ui, sans-serif, 'Apple Color Emoji', 'Segoe UI Emoji'"
    fontSize: "clamp(1.875rem, 4vw, 2.25rem)"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "-0.025em"
  headline:
    fontFamily: "ui-sans-serif, system-ui, sans-serif"
    fontSize: "1.5rem"
    fontWeight: 600
    lineHeight: 1.3
  title:
    fontFamily: "ui-sans-serif, system-ui, sans-serif"
    fontSize: "1.125rem"
    fontWeight: 600
    lineHeight: 1.4
  body:
    fontFamily: "ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.75rem"
    fontWeight: 500
    lineHeight: 1.4
    letterSpacing: "0.05em"
rounded:
  field: "0.5rem"
  box: "0.75rem"
  pill: "9999px"
spacing:
  xs: "0.25rem"
  sm: "0.5rem"
  md: "1rem"
  lg: "1.5rem"
  xl: "2rem"
components:
  button-primary:
    backgroundColor: "{colors.signal-red}"
    textColor: "{colors.console-text}"
    rounded: "{rounded.field}"
    padding: "0.5rem 1rem"
  button-primary-hover:
    backgroundColor: "oklch(52% 0.22 27.33)"
    textColor: "{colors.console-text}"
  button-soft:
    backgroundColor: "oklch(57% 0.24 27.33 / 0.15)"
    textColor: "{colors.signal-red}"
    rounded: "{rounded.field}"
    padding: "0.5rem 1rem"
  badge-success:
    backgroundColor: "oklch(64% 0.15 160 / 0.15)"
    textColor: "{colors.complete-green}"
    rounded: "{rounded.pill}"
    padding: "0.125rem 0.5rem"
  badge-warning:
    backgroundColor: "oklch(72% 0.17 70 / 0.15)"
    textColor: "{colors.caution-amber}"
    rounded: "{rounded.pill}"
    padding: "0.125rem 0.5rem"
  badge-info:
    backgroundColor: "oklch(62% 0.19 240 / 0.15)"
    textColor: "{colors.queue-blue}"
    rounded: "{rounded.pill}"
    padding: "0.125rem 0.5rem"
  badge-error:
    backgroundColor: "oklch(58% 0.24 27 / 0.15)"
    textColor: "{colors.fault-red}"
    rounded: "{rounded.pill}"
    padding: "0.125rem 0.5rem"
  input-default:
    backgroundColor: "transparent"
    textColor: "{colors.console-text}"
    rounded: "{rounded.field}"
    padding: "0.5rem 0.75rem"
---

# Design System: Ytdarr

## 1. Overview

**Creative North Star: "The Control Room"**

Ytdarr is an operations console for your media pipeline. The interface is a focused instrument panel: every element communicates system state, every control is within reach, and nothing decorates for decoration's sake. The design philosophy descends from broadcast control rooms and industrial monitoring: information density earned through clear hierarchy, not crammed in through small fonts.

The system is flat, fast, and honest. Surface tone establishes depth. Signal Red marks what needs attention. The rest stays quiet. When a user opens Ytdarr, they should know the health of their pipeline in under two seconds without reading a word.

This system explicitly rejects YouTube's engagement-driven density, Sonarr's raw utilitarian default, and generic SaaS dashboard templates with hero metric cards and gradient accents. Ytdarr borrows the *arr mental model (channels as series, videos as episodes) but executes it with its own visual voice: tighter, darker, more purposeful.

**Key Characteristics:**
- **State-first hierarchy.** Status badges, progress bars, and queue counts are the loudest elements. Chrome recedes.
- **Tactile controls.** Buttons, toggles, and actions feel like physical switches. Immediate, confident feedback.
- **Tonal depth.** No shadows. Surface layers are distinguished by luminance steps (base-100 → base-200 → base-300).
- **Operational red.** Signal Red is reserved for primary actions and active states. Its rarity on any given screen is the point.
- **Density without clutter.** Tables and lists show enough to decide without drilling down, but whitespace rhythm prevents wall-of-text fatigue.

## 2. Colors: The Signal Palette

The palette is built for operational clarity. Signal Red carries intent; everything else serves as neutral ground. All colors are authored in OKLCH for perceptual uniformity across the light and dark themes.

### Primary
- **Signal Red** (`oklch(57% 0.24 27.33)`): The operational accent. Primary buttons, active navigation states, and download progress. Used on no more than 10% of any given screen surface.
- **Bright Signal** (`oklch(62% 0.25 27.33)`): Dark theme highlight variant. Accent-weight elements and hover emphasis.
- **Deep Signal** (`oklch(52% 0.24 27.33)`): Light theme emphasis variant. Deeper red for high-contrast surfaces.

### Secondary
- **Console Slate** (`oklch(55% 0.02 260)` dark / `oklch(50% 0.03 260)` light): Secondary actions, muted controls, and supporting text. A cool blue-gray that recedes behind Signal Red.

### Neutral
- **Deep Console** (`oklch(21% 0.006 285.885)`): Dark theme primary surface (base-100). The resting state of the control room.
- **Panel Dark** (`oklch(17.5% 0.005 285.885)`): Dark theme sidebar and elevated panels (base-200).
- **Console Floor** (`oklch(14.5% 0.004 285.885)`): Dark theme deepest layer (base-300). Borders and dividers.
- **Console White** (`oklch(99% 0 0)`): Light theme primary surface. Near-white, not pure white.
- **Panel Light** (`oklch(96.5% 0.002 286.375)`): Light theme sidebar and elevated panels.
- **Console Edge** (`oklch(92% 0.004 286.32)`): Light theme borders and dividers.
- **Charcoal Steel** (`oklch(30% 0.01 260)` dark / `oklch(40% 0.015 260)` light): Elevated surface gray for neutral containers.
- **Console Text** (`oklch(96% 0.002 286.375)` dark / `oklch(21% 0.006 285.885)` light): Primary text color. Not pure white or black; tinted faintly toward the blue-gray neutral.

### Semantic Status
- **Queue Blue** (`oklch(62% 0.19 240)` dark / `oklch(58% 0.2 250)` light): Queued items, informational state.
- **Complete Green** (`oklch(64% 0.15 160)` dark / `oklch(62% 0.16 165)` light): Downloaded, success, completed state.
- **Caution Amber** (`oklch(72% 0.17 70)`): Downloading in progress, warnings, post-processing.
- **Fault Red** (`oklch(58% 0.24 27)`): Errors, missing files, failed downloads. Deliberately close to Signal Red in hue to maintain palette cohesion but slightly desaturated to avoid confusion with primary actions.

### Named Rules
**The Signal Scarcity Rule.** Signal Red appears on no more than 10% of any screen's surface area. Its power comes from rarity. If a screen feels "too red," something is using Signal Red decoratively instead of operationally.

**The No Pure Black, No Pure White Rule.** Every neutral is tinted toward the blue-gray hue family (285°). `#000` and `#fff` are prohibited. The darkest surface is `oklch(14.5% 0.004 285.885)`; the lightest is `oklch(99% 0 0)`.

## 3. Typography

**System Sans:** `ui-sans-serif, system-ui, sans-serif` with emoji fallbacks.

No custom webfonts. The system stack loads instantly, renders crisply at small sizes, and feels native on every platform. Typography hierarchy is achieved through weight and size contrast, not font pairing.

**Character:** Technical, clean, and legible at high density. The system font stack feels native and fast, matching the "snappy" personality. Weight contrast (400 body vs. 600–700 headings) creates hierarchy without needing a display face.

### Hierarchy
- **Display** (700, `clamp(1.875rem, 4vw, 2.25rem)`, line-height 1.2, letter-spacing -0.025em): Page titles and hero headings. Channel names in the hero header banner.
- **Headline** (600, 1.5rem, line-height 1.3): Section headings. "All Videos," "Playlists," settings group titles.
- **Title** (600, 1.125rem, line-height 1.4): Card headings, table group labels, modal titles.
- **Body** (400, 0.875rem, line-height 1.5): Default text. Table cells, descriptions, form help text. Max line length: 65ch.
- **Label** (500, 0.75rem, line-height 1.4, letter-spacing 0.05em, uppercase): Table column headers, metadata labels ("Upload Date," "Status"), badge text.

### Named Rules
**The 14px Floor Rule.** Body text never drops below 0.875rem (14px). Label text at 0.75rem (12px) is reserved for secondary metadata and table headers only. Nothing smaller exists in the system.

## 4. Elevation

Ytdarr is flat by design. Depth is conveyed exclusively through surface tone, not shadows.

The three-tier tonal system (base-100 → base-200 → base-300) establishes spatial hierarchy. The sidebar sits on base-200, the main content area on base-100, and borders/dividers use base-300. This progression reads as depth without any box-shadow.

The daisyUI `--depth: 1` token is set but effectively unused for custom components. If a future component needs perceived lift (a dropdown menu, a tooltip), use a single ambient shadow (`0 4px 24px oklch(0% 0 0 / 0.12)`) rather than multiple stacked shadows. The shadow should be diffuse and nearly invisible at rest.

### Named Rules
**The Flat-by-Default Rule.** Surfaces are flat. Tonal steps (base-100/200/300) create depth. Shadows appear only for floating overlays (dropdowns, tooltips, modals) and never for cards, panels, or sections. If you're reaching for `box-shadow` on a static element, use a tonal background step instead.

## 5. Components

### Buttons
- **Shape:** Gently rounded corners (8px / 0.5rem).
- **Primary:** Signal Red background, white text. daisyUI `btn btn-primary`. Padding inherited from daisyUI scale. Used for destructive-weight actions (delete, queue download) and primary submission.
- **Soft / Default:** Signal Red tinted background (primary at 15% opacity), Signal Red text. daisyUI `btn btn-primary btn-soft`. The default when no variant is specified. Used for secondary CTA and contextual actions.
- **Ghost:** Transparent background, icon-only or text. daisyUI `btn btn-ghost`. Table row actions, toolbar controls.
- **Hover:** Darkened background (2 lightness steps), subtle transform scale. Transition: 150ms ease-out.
- **Focus:** Visible ring (2px, offset 2px) using the primary color at reduced opacity.

### Status Badges
- **Style:** Pill-shaped (border-radius: 9999px). Icon + text, never color alone. Font size: label scale (0.75rem, 500 weight).
- **Available:** Muted neutral background (base-200), subdued text (base-content/60). Cloud-download icon.
- **Queued:** Queue Blue at 15% opacity background, Queue Blue text. Clock icon.
- **Downloading:** Caution Amber at 15% opacity background, Caution Amber text. Spinning arrow-path icon (respects `prefers-reduced-motion`).
- **Downloaded:** Complete Green at 15% opacity background, Complete Green text. Check-badge icon.
- **Missing / Error:** Fault Red at 15% opacity background, Fault Red text. Exclamation-triangle icon.

### Data Pill
- **Style:** Full pill radius (9999px). Border + fill variant system matching daisyUI semantic colors. Three sizes: sm (0.75rem text), md (0.875rem), lg (1rem).
- **Hover:** Background darkens 10%. Transition: 200ms.
- **Focus:** Ring with offset, matching variant color.

### Inputs / Fields
- **Style:** daisyUI `input` / `select` / `textarea` classes. Border stroke from theme, rounded corners (0.5rem).
- **Focus:** daisyUI default focus ring. Border color shifts to primary.
- **Error:** `input-error` / `select-error` class applies Fault Red border. Error message below with exclamation-circle icon, Fault Red text, 0.875rem.
- **Disabled:** Reduced opacity, cursor-not-allowed.

### Navigation (Sidebar)
- **Style:** Fixed-width sidebar (14rem / `w-56`), base-200 background, base-300 border-right.
- **Items:** Rounded-lg (0.5rem), px-3 py-2 padding. Heroicons at 1rem (size-4) leading each label.
- **Default state:** base-content text, transparent background.
- **Hover:** base-300 at 60% opacity background. 150ms transition.
- **Active:** Signal Red at 10% opacity background, Signal Red text, semibold weight. The active indicator is a tonal fill, not a side stripe.
- **Mobile:** Drawer-style overlay with backdrop. Same styling as desktop, slightly wider (16rem / `w-64`).

### Progress Bars
- **Track:** base-300 background, full pill radius, 0.5rem height.
- **Fill:** Signal Red (in-progress), Complete Green (100%), Caution Amber pulsing (post-processing). Transition: 300ms.
- **Indeterminate:** Animated gradient sweep (transparent → primary → transparent) with pulse. 40% width bar.
- **Meta text:** Below the bar. Label-scale text (0.75rem), base-content at 70% opacity. Status left-aligned, speed/ETA right-aligned.

### Tables (Video Table)
- **Style:** daisyUI `table table-sm`. Clean grid with minimal borders.
- **Header:** Label scale (0.75rem), uppercase, letter-spacing 0.05em, base-content at 50% opacity.
- **Row hover:** base-200 at 50% opacity. Transition-colors.
- **Thumbnails:** 4rem × 2.25rem, rounded corners (0.25rem), object-cover. Lazy-loaded. Placeholder: base-300 with centered play icon.

### Theme Toggle
- **Style:** Three-segment pill (system / light / dark). base-300 track, active segment highlighted with base-100 fill and brightness boost.
- **Icons:** Heroicons micro variants (computer-desktop, sun, moon) at 1rem.
- **Transition:** Sliding indicator, CSS `transition-[left]`.

## 6. Do's and Don'ts

### Do:
- **Do** use Signal Red only for primary actions and active states. Its scarcity is intentional.
- **Do** communicate status through icon + text together. A color-blind user should understand every state.
- **Do** use the three-tier tonal system (base-100/200/300) for spatial hierarchy instead of shadows.
- **Do** respect `prefers-reduced-motion` by disabling all CSS animations and transitions.
- **Do** maintain WCAG AA contrast ratios in both themes. Test each semantic color against its content pair.
- **Do** use daisyUI semantic classes (`btn-primary`, `alert-info`, `badge`) as the component foundation. Custom styling extends them; it does not replace them.
- **Do** keep tables dense but readable. Label-scale headers, body-scale cells, generous horizontal padding.

### Don't:
- **Don't** use Signal Red decoratively. No red gradients, no red borders as accents, no red backgrounds larger than a button.
- **Don't** build hero metric dashboards with big numbers, small labels, and gradient cards. That's a SaaS template, not a control room.
- **Don't** use border-left or border-right greater than 1px as a colored accent stripe on cards or list items.
- **Don't** use gradient text (`background-clip: text` with gradient). Emphasis comes from weight and size.
- **Don't** use identical card grids with icon + heading + text repeated in a row. If content is tabular, use a table. If it's heterogeneous, design for the differences.
- **Don't** clone YouTube's layout patterns. No recommendation carousels, no engagement feeds, no autoplay UI.
- **Don't** clone Sonarr's visual treatment verbatim. Ytdarr borrows the mental model, not the stylesheet.
- **Don't** use modals as the first design impulse. Inline editing, expandable rows, and slide-over panels should be exhausted first.
- **Don't** animate CSS layout properties (width, height, top, left). Use transform and opacity only.
- **Don't** use glassmorphism (backdrop-blur + transparency) decoratively. Reserve for rare, justified overlays.
- **Don't** use pure `#000` or `#fff`. Every surface has a faint blue-gray tint.
