# Changelog

All notable changes to Agent Canvas are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version tags match GitHub Releases (`vMAJOR.MINOR.PATCH`).

## [Unreleased]

### Changed
- **Multi-family widget kinds (PLAT-126):** compiled identities are `one` through `twelve` (`AgentCanvas.one`, … `AgentCanvas.twelve`). Each kind supports Small, Medium, Large, and Extra Large. Size is chosen when you place the widget; the same document can show at two sizes without a second write.
- MCP `canvas` accepts those definition ids and still accepts legacy size-first ids (`sm-one`, …) as aliases of **one / two / three** only. `list_canvases` reports `placedFamilies` from a WidgetCenter snapshot. Unplaced definitions have no family; density defaults to medium unless you pass `size=`.
- lastRender / preview artifacts are per `(definition, family)` (`one.md.render.json`, `previews/one.md.png`) so small and large placements do not overwrite each other.
- Documents live at `canvases/{definition}.json`. Leftover `sm-one.json` / `md-one.json` files are read as aliases (prefer non-empty `md-*`, else first non-empty; never merge).

### Breaking
- **Re-add widgets.** Old size-baked kinds (`AgentCanvas.sm-one`, …) go empty and cannot be remapped. iPhone does not offer Extra Large.

## [0.2.10] - 2026-08-12

### Added
- **Run Canvas on startup:** Settings → General → Startup toggle registers the menu bar host as a login item (`SMAppService`) so Agent Canvas comes back after reboot without opening it from Applications
- iOS subscribe-only app scaffold (sign-in + cloud subscribe → App Group / WidgetKit)

### Fixed
- Notification permission UX when enabling content-change alerts
- Canvas preview chrome adapts for light and dark appearance
- Notarized DMG includes an Applications symlink for drag-install

### Changed
- Shared Apple sources live under `platforms/apple`

## [0.2.9] - 2026-07-28

### Added
- **Content-change notifications:** opt-in system banners when an agent updates canvas content (`contentEqual` gate), with per-canvas mute and coalesced multi-slot updates
- **Check for Updates…** in the menu bar (above Quit) and Settings → General → App
- Privacy link in Settings → General (moved out of the menu bar)
- `just release-preflight` + ship checklist in `.github/CI.md` (clean tree, menu/settings UX contract, Release build)

### Changed
- Menu bar labels drop unnecessary ellipses; Privacy no longer listed in the menu bar dropdown

## [0.2.8] - 2026-07-28

### Notes
- Follow-up build to verify Sparkle updates from 0.2.7 (build 7 → 8). No product changes.

## [0.2.7] - 2026-07-28

### Added
- **Sparkle in-app updates:** Check for Updates… menu item, automatic background checks, EdDSA-signed `appcast.xml` + universal zip on GitHub Releases (`SUFeedURL` → `…/releases/latest/download/appcast.xml`)

### Notes
- First update-*capable* build. Testers on 0.2.7 will receive 0.2.8+ via Sparkle. Install from the notarized DMG (not an unsigned zip).

## [0.2.6] - 2026-07-28

### Added
- Org-visibility publish from the host (sign-in required): public vs organization, org picker from auth `GET /api/v1/me/organizations`, auto-push updates on canvas reload
- `agentcanvas://subscribe?slug=` deep link with slot picker (PLAT-105)
- DEBUG-only **Dev** settings tab (cloud, OAuth, shares/subscriptions, seed demos)
- Empty-canvas chrome with how-to affordance

### Changed
- Platform OAuth client fixed as `velox-agent-canvas`; scopes include `canvas:read` / `canvas:write`; `resource` on token/refresh only
- Settings General uses grouped `Form` layout; cloud debug controls moved out of General
- Publish / Subscribe live in the canvas page menu (sheets) rather than always-on form blocks

### Fixed
- Org list failures surface as errors instead of “No organizations found”
- Settings detail no longer remounts every poll tick (publish form / scroll preserved)

<!--
## [0.2.0] - YYYY-MM-DD

### Added
### Changed
### Fixed
-->
