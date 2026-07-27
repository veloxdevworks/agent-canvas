# Agent Canvas

**Glanceable desktop canvases that AI agents can update.**

You place fixed widgets on the Mac desktop. Agents (Claude, Cursor, and other MCP clients) write structured content to them over a local [MCP](https://modelcontextprotocol.io) server. Rendering is native WidgetKit—not a floating webview.

Product site and downloads: *coming soon* (this repo is the open source / engineering home).

---

## Why it exists

Agents are good at fetching data and drafting summaries, but they have nowhere durable and glanceable to put the result. Agent Canvas gives them a small set of **named, size-aware surfaces** (`sm-one`, `md-two`, …) so updates land where the user already looks—without inventing layout engines or fighting multi-size widget thrash.

**Principles (v1)**

- **Native where it shows** — system widgets, system chrome  
- **Declarative content** — JSON schema; agents never touch SwiftUI  
- **Fixed addresses** — size × slot, not unlimited instances  
- **Local by default** — data under `~/.velox/canvas`; cloud publish is optional and Release-gated (see below)  
- **Density-aware** — hard budgets per size; agents get clip feedback and optional PNG previews  

Privacy details: [`PRIVACY.md`](./PRIVACY.md). Third-party notices: [`NOTICE`](./NOTICE).

---

## What’s available today

| Area | Status |
|------|--------|
| **macOS host** | Menu bar app (stays running with zero windows); status, how-to, connect wizard |
| **Widgets** | 12 WidgetKit kinds: **sm / md / lg / xl** × **one / two / three** |
| **MCP server** | Local stdio (`agent-canvas-mcp`) for Cursor, Claude Desktop, etc. |
| **Content** | Schema v1: header, text, metrics, chart, list, image, spacer, progress, divider, keyValue, badges; optional `tone`/`emphasis`; detail-only `group`; optional `onOpen` / list `action` and `detail`; optional full-bleed `cover` |
| **Agent feedback** | Density reports, predicted clip (reference packer), last-render meta, **`preview_canvas`** (PNG of the real tile); cover aspect warnings from `set_canvas_cover` |
| **Portability** | Layout constants + packer live in Rust; macOS renderer consumes generated `LayoutSpec`; `schema/conformance` goldens |
| **Data** | `~/.velox/canvas/canvases/{id}.json`; assets under `~/.velox/canvas/assets/` |
| **Distribution** | Direct / developer install (not Mac App Store) |

### Canvas ids

| | **one** | **two** | **three** |
|--|---------|---------|-----------|
| **sm** | `sm-one` | `sm-two` | `sm-three` |
| **md** | `md-one` | `md-two` | `md-three` |
| **lg** | `lg-one` | `lg-two` | `lg-three` |
| **xl** | `xl-one` | `xl-two` | `xl-three` |

The id encodes density: updating `sm-one` always means a small glance surface.

### MCP tools (summary)

| Tool | Role |
|------|------|
| `update_canvas` / `update_canvas_simple` | Write content |
| `set_canvas_cover` / `clear_canvas_cover` | Full-bleed custom PNG/JPEG (agent-generated) |
| `get_canvas` / `list_canvases` | Read state + layout hints |
| `get_layout_guide` | Size budgets + cover target pixels for agents |
| `preview_canvas` | PNG snapshot (host must be running) |
| `share_canvas` / `update_shared_canvas` / `unshare_canvas` / `list_shared` | Publish to canvas cloud (**dev only**, see below) |
| `clear_canvas` | Empty a surface |

**Cloud publish / subscribe (pre-release, debug only)**

| Surface | Gate |
|---------|------|
| MCP `share_*` tools | Debug + `AGENT_CANVAS_CLOUD_PUBLISH=1` (release needs `--features cloud-publish` too) |
| Host Settings → General → **Cloud (debug)** | Debug + env **or** in-app toggle |

```bash
export AGENT_CANVAS_CLOUD_PUBLISH=1
export AGENT_CANVAS_API_URL=https://canvas.velox.test   # optional
export AGENT_CANVAS_OAUTH_CLIENT_ID=<public-client-id>  # optional; or save in Settings
# MCP:
cargo run -p agent-canvas-mcp -- stdio
# Host (Debug): Settings → General → enable Cloud, Sign in with Velox
```

**Host UI:** API base URL, default poll interval, Velox OAuth (PKCE public client → `agentcanvas://oauth/callback`), share/subscription overview, per-slot publish & subscribe on each canvas page.  

**Tokens (separate Keychain services):**

- User OAuth access/refresh — `com.velox.agentcanvas.oauth`
- Per-slug edit tokens for shared canvases — `com.velox.agentcanvas.canvas-edit-token`

Register the OAuth public client once (portal/DCR) with redirect URI exactly `agentcanvas://oauth/callback`, PKCE S256, no client secret. Resource/audience = canvas origin (e.g. `https://canvas.velox.test`).

Keep the **host app running** so widgets reload when the agent writes. Closing windows does not quit—use **Quit** from the menu bar.

---

## What’s next

Rough direction (not a commitment to dates):

- **GitHub Releases** — Linux MCP on tags; notarized macOS DMG via private [`agent-canvas-release`](https://github.com/veloxdevworks/agent-canvas-release)  
- **In-app updates** — Sparkle (“Check for Updates…” + optional auto-check)  
- **Polished packaging** — DMG layout polish; Connect already prefers the bundled MCP helper  

- **Schema / density** — promote proven `group` layouts from detail → glance; more leaves as demand appears  
- **Cross-platform** — shared schema + MCP + layout_spec; native shells (Windows Adaptive Cards, KDE QML) later  

Design notes and older architecture drafts live in [`plan.md`](./plan.md) (some sections still use early naming).

### CI

- **Public (this repo):** Linux validation on PRs/pushes (fmt, clippy, tests, MCP build).  
- **Private release:** [`agent-canvas-release`](https://github.com/veloxdevworks/agent-canvas-release) — trusted macOS builds on the org self-hosted runner (no public PR traffic on the Mac).  

See [`.github/CI.md`](./.github/CI.md).

---

## Develop (macOS)

Requires Xcode, [Just](https://github.com/casey/just), Rust, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd agent-canvas

just macos-team TEAM=XXXXXXXXXX   # once
just macos-install                # build → ~/Applications
just macos-run

just build-rust
just mcp-serve                    # or point Cursor/Claude at target/release/agent-canvas-mcp
just mcp-seed canvas=md-one
```

Useful recipes: `just --list`, `just macos-diagnose`, `just macos-widgets-reset`, `just mcp-paths`.

### Repo layout

```
agent-canvas/
├── schema/                 # JSON Schema + fixtures
├── crates/
│   ├── agent-canvas-core/  # ids, validation, storage
│   └── agent-canvas-mcp/   # stdio MCP server
├── platforms/macos/        # Host + WidgetKit (XcodeGen)
├── scripts/macos/          # install, diagnose, icons
└── plan.md
```

---

## License & contact

[MIT](./LICENSE) — see [LICENSE](./LICENSE). Feedback: [feedback@veloxdevworks.com](mailto:feedback@veloxdevworks.com).

Repository: [github.com/veloxdevworks/agent-canvas](https://github.com/veloxdevworks/agent-canvas)
