# Changelog

All notable changes to Agent Canvas are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version tags match GitHub Releases (`vMAJOR.MINOR.PATCH`).

## [Unreleased]

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
