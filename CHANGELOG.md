# Changelog

All notable changes to Agent Canvas are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version tags match GitHub Releases (`vMAJOR.MINOR.PATCH`).

## [Unreleased]

### Added
- Local MCP server and macOS WidgetKit host (12 size×slot canvases)
- Density packing, layout guide, and `preview_canvas` PNG feedback
- Connect wizard for Cursor / Claude Desktop
- Lean GitHub Actions CI (Linux by default; macOS opt-in)
- **Cloud publish (PLAT-82):** `share_canvas` / `update_shared_canvas` / `unshare_canvas` / `list_shared`, HTTP client (`AGENT_CANVAS_API_URL`), Keychain edit tokens
- **Canvas actions:** document `onOpen`, optional `detail` sections, and per-list-item `action` (`expand` / `url` / `file` / `noop`). Widget taps dispatch via `agentcanvas://action…`; `url` allows http/https/mailto only; `file` reveals in Finder. Per-row taps on md/lg/xl; sm is whole-tile only.
- **Portable layout policy:** Rust `layout_spec` + reference packer; committed `LayoutSpec.generated.swift`; `schema/conformance` goldens verified in Linux CI and Swift unit tests.
- **Schema expressiveness:** semantic `tone` / `emphasis` tokens; leaf types `progress`, `divider`, `keyValue`, `badges`; detail-only `group` container (depth ≤ 2). JSON Schema generated from core (`just gen-schema`).
- **Detail window sizing:** expand window hugs content height (min ~200pt, max ~720pt / 85% of screen) and scrolls when full.
- **Full-bleed covers:** document `cover` (alt + fit tokens) fills the glance tile; agents send base64 via `set_canvas_cover` / `clear_canvas_cover`; bytes land in content-addressed `~/.velox/canvas/assets/`. Inline `image` sections decode for real; height tokens `small|medium|large`. Layout guide documents recommended 2× pixel sizes and Dark Mode / a11y tradeoffs.

### Planned
- Notarized app archives on GitHub Releases
- Sparkle in-app updates

<!--
## [0.2.0] - YYYY-MM-DD

### Added
### Changed
### Fixed
-->
