# Agent Canvas — Design Plan (v1)

**Status:** draft for iteration  
**Primary platform:** macOS (WidgetKit)  
**Cross-platform:** schema + daemon shared; native widget shells per OS later  
**Repo home:** `velox/agent-canvas` (not macOS-locked)

---

## Vision

A set of glanceable desktop canvases that agents can write to. Users place a small fixed number of canvases on the desktop (v1: three named slots). Any agent host (Claude, Grok, Cursor, ChatGPT Desktop, custom tools) updates a canvas via a local MCP server. Content is declarative JSON; the shell renders it with native widget UI so it feels like part of the OS, not a floating webview.

---

## Core Principles

1. **Native where it shows** — System widgets on each platform, not “always-on-top app windows pretending to be widgets.”
2. **Declarative content** — Agents emit a small JSON schema; they never touch layout engines.
3. **Fixed slots, not infinite instances** — `one` / `two` / `three` so agents and users share a stable address space with zero config.
4. **Tiny primitive set** — Prefer reliable agent generation over expressiveness.
5. **Local-only in v1** — No cloud, no multi-device.
6. **Cross-platform contract, platform shells** — One schema + one daemon API; renderers are OS-specific.

---

## Scope (v1)

### In scope

| Area | Detail |
|------|--------|
| Canvases | Three slots: `one`, `two`, `three` |
| macOS widgets | WidgetKit families: `systemSmall` → `systemExtraLarge` (and desktop placement where the OS supports it) |
| Content | JSON schema v1 with a small primitive set |
| Agent API | Local MCP tools: update / clear / get / list |
| Persistence | Per-canvas JSON on disk under a well-known app data path |
| Host app | Lightweight settings, empty-state onboarding, daemon status, “clear all” |
| Update path | Write full JSON → notify platform reload (no aggressive polling) |

### Out of scope (v1)

- Unlimited dynamic widget instances
- Complex nested / absolute layout
- Cloud sync or multi-device
- Custom fonts beyond system fonts
- Windows / Linux **native** widget shells (contract only; optional “preview window” in host app)
- Agent-driven partial JSON patches (full document replace only)

### Actions (shipped)

Declarative intents shared by document `onOpen` and list `items[].action`:

| Type | Behavior |
|------|----------|
| `expand` | Open host detail window (`detail.sections` if set, else `sections`). **Default** when `onOpen` omitted. |
| `url` | Open http/https/mailto in the system handler (no credentials; other schemes rejected). |
| `file` | Reveal path in Finder (never launches). |
| `noop` | Do nothing. |

Widget deep links are pointers (`agentcanvas://action?id=…` / `&section=&item=&v=`). Host re-reads JSON and re-validates. `systemSmall` supports whole-tile `onOpen` only; md/lg/xl can tap list rows.

---

## Architecture recommendation

### Do not put the widget UI in Tauri

**Tauri is a good host for the daemon and settings app; it is not a substitute for WidgetKit.**

| Layer | What it is | Why |
|-------|------------|-----|
| **Native widget shell** | macOS: WidgetKit + SwiftUI (+ Swift Charts) | Only path to real desktop / Notification Center widgets and “100% native” |
| **Daemon + MCP** | Rust binary (or in-process in the host app) | Cross-platform, matches patterns already used in `remex` |
| **Host / settings app** | Tauri **or** pure Swift — either is fine | Manages daemon lifecycle, onboarding, debug inspector |
| **Contract** | JSON schema + storage layout + MCP tools | Shared forever; Windows/Linux plug in later |

**Why not Tauri-only “desktop widgets”?** Floating Tauri windows can look like dashboards, but they miss system placement, WidgetKit budgets/timeline behavior, and the native glanceable look. On Windows/Linux, a Tauri window is a reasonable *fallback*; it is not the long-term native story.

**Why not pure Swift for everything?** A Swift-only MCP server works on Mac, but locks the agent surface to macOS packaging and forces a rewrite for other OS daemons. Rust (or Node) for MCP keeps the repo honest about multi-platform.

**Recommended split for this monorepo:**

```
agent-canvas/
├── plan.md                 # this document
├── schema/                 # JSON Schema + golden fixtures (source of truth)
├── crates/
│   └── agent-canvas-core/  # validate, store, reload hooks, MCP tool impl
│   └── agent-canvas-mcp/   # stdio + optional streamable-HTTP server binary
├── apps/
│   └── host/               # Tauri (or Swift) settings + daemon launcher
└── platforms/
    └── macos/              # Xcode: main app thin shell + Widget Extension
        # later: windows/ (Widget Provider + Adaptive Cards)
        # later: linux/   (KDE Plasmoid; GNOME TBD)
```

### Data path and process model (critical)

Agents spawn MCP over **stdio** as a child process. That process is **not** signed into your App Group. Design storage so any local process can write, and the widget can read.

**Recommended storage root (cross-platform friendly):**

| OS | Path |
|----|------|
| macOS / all | `~/.velox/canvas/canvases/{sm-one,md-one,…}.json` |
| Override | `AGENT_CANVAS_DATA_DIR` or MCP `--data-dir` |

**macOS widget read path (v1, shipped in scaffold):**

1. MCP / host write JSON under `~/.velox/canvas/canvases/`.
2. Sandboxed widget reads that path via `temporary-exception.files.home-relative-path.read-write` on `/.velox/canvas/`.
3. Host polls `.reload-request` and calls `WidgetCenter.shared.reloadTimelines(ofKind:)`.

**App Groups:** deferred until packaging/MAS. Re-introduce when automatic provisioning for `group.com.velox.agentcanvas` is set up in the developer portal.

**MCP transport (v1):** stdio binary (`agent-canvas-mcp`). HTTP/in-host MCP can follow (remex-style) without changing the JSON contract.

### Cross-platform widget reality (do not lock the repo; do not fake parity)

| Platform | Native widget API | v1 stance |
|----------|-------------------|-----------|
| **macOS** | WidgetKit + SwiftUI | **Ship** |
| **Windows 11** | Widget providers + **Adaptive Cards** (Windows App SDK) | Schema-compatible backend later; different renderer |
| **Linux (KDE)** | Plasma widgets (QML plasmoids) | Best native Linux path later |
| **Linux (GNOME)** | No first-class desktop widget SDK | Host “preview window” only, or skip |

**Contract that stays portable:**

- Canvas IDs: `one` \| `two` \| `three`
- JSON Schema version field
- File layout under app data
- MCP tool names and parameter shapes

**What will not stay portable:** SwiftUI views, Adaptive Card templates, QML. That is expected.

### Portability gate (new primitives)

Every new section type or styling knob must pass before merge:

1. Expressible in Adaptive Cards and QML (at least degraded)?
2. Styling via semantic tokens (`tone` / `emphasis`), never raw colors or point sizes?
3. No absolute positioning or platform-only capability in the JSON contract?
4. Height derivable from Rust `layout_spec` without platform font metrics?
5. Policy lands in Rust (`section_meta` / `layout_spec` / packer); `platforms/macos/Shared/` gains rendering only?

**Cover images (2026-07):** Passed. Adaptive Cards `backgroundImage` + `fillMode: cover` / QML `Image { fillMode: PreserveAspectCrop }` map cleanly; `fit` and image `height` are tokens; cover height is the whole tile; asset store + validation live in Rust (`assets`, schema, packer); Swift only decodes/renders. Tradeoff documented for agents: covers are not Dark Mode / Dynamic Type aware.

**Named icons (2026-07):** Passed. Curated `iconName` enum in the JSON contract (never SF Symbol / Lucide strings). Leaf `type=icon` maps to Adaptive Cards `Image` / QML icon font (or text fallback); optional `icon` shorthand on `header` / list items / metrics items is host chrome only. Size via `sm|md|lg` tokens; heights from `layout_spec`; validation and packing in Rust; macOS maps names → SF Symbols in `CanvasIcon`.

### Unknown section types (intentional asymmetry)

| Layer | Behavior |
|-------|----------|
| **Rust write path** (`update_canvas`) | Strict — unknown `type` fails deserialize / validate |
| **Swift widget read** | Tolerant — unknown `type` → `.unknown` (forward compatible) |

Agents always go through the validating MCP/core write path; widgets may briefly see newer documents after a host update.

---

## Content schema (v1)

Agents write a full document per canvas (replace, not patch):

```json
{
  "version": 1,
  "updatedAt": "2026-07-24T18:42:00Z",
  "title": "Optional canvas title",
  "sections": [
    {
      "type": "header",
      "text": "Jira Throughput",
      "subtitle": "Last 7 days"
    },
    {
      "type": "metrics",
      "items": [
        { "label": "Tickets Closed", "value": "47", "trend": "+12%" },
        { "label": "Avg Cycle Time", "value": "2.3d", "trend": "-0.4d" }
      ]
    },
    {
      "type": "chart",
      "chartType": "bar",
      "title": "Daily Closures",
      "data": [
        { "label": "Mon", "value": 8 },
        { "label": "Tue", "value": 12 }
      ]
    },
    {
      "type": "list",
      "title": "Open High Priority",
      "items": [
        { "primary": "API rate limiting", "secondary": "ENG-4821", "badge": "P1" }
      ]
    },
    {
      "type": "image",
      "source": "data:image/png;base64,...",
      "caption": "Optional"
    },
    {
      "type": "text",
      "content": "Plain paragraphs; basic markdown optional in v1.1"
    },
    { "type": "spacer" }
  ]
}
```

### Primitives

| Type | Purpose | Notes |
|------|---------|--------|
| `header` | Title + optional subtitle / `icon` | Prefer one near the top |
| `text` | Body copy | v1: plain text; soft-wrap |
| *(document)* `onOpen` | Tile tap | Optional `Action`; default expand |
| *(document)* `detail` | Expand layout | Optional `{ sections }`; not in glance density |
| *(list item)* `action` | Row tap | Optional `Action` |
| `metrics` | 2–4 key numbers + optional trend / `icon` | Horizontal on large; stacked on small |
| `chart` | `bar` \| `line` \| `pie` \| `gauge` | Swift Charts on macOS; degrade gracefully on tiny sizes |
| `list` | Rows | `primary`, optional `secondary`, optional `badge`, optional `icon` |
| `image` | Contained image | Prefer small base64 or `file://` under app data; cache; size limits |
| `spacer` | Vertical gap | Optional `size`: `sm` \| `md` \| `lg` |
| `progress` | Progress bar | `value` (+ optional `max`, `tone`); degrade to text on Adaptive Cards |
| `divider` | Horizontal rule | |
| `keyValue` | Label/value rows | Optional per-item `tone` |
| `badges` | Chip row | Optional per-item `tone` |
| `icon` | Named glyph leaf | Curated `name` + optional `tone` / `size` (`sm`\|`md`\|`lg`); composable in detail `group` |
| *(header / list / metrics)* `icon` | Leading glyph shorthand | Same curated names as `type=icon` |
| `group` | Flex row/column | **Detail-only** (not glance); depth ≤ 2; children ≤ 6; atomic for clipping |
| *(items/sections)* `tone` / `emphasis` | Semantic style | Never hex/fonts; maps to system + Adaptive Cards color/weight |

**Schema rules (enforce in `agent-canvas-core`):**

- `version` must be `1`
- Max sections (e.g. 12) and max list items (e.g. 20) so widgets stay glanceable
- Reject / strip oversized images with a clear MCP error
- Unknown section types: skip with warning in host debug log (do not fail whole canvas)

Publish a **JSON Schema** file agents (and humans) can reference; keep Swift `Codable` and Rust structs generated from or tested against the same fixtures.

---

## MCP interface

| Tool | Args | Behavior |
|------|------|----------|
| `update_canvas` | `canvas`: `one`\|`two`\|`three`, `content`: object | Validate → write → reload that kind |
| `clear_canvas` | `canvas` | Write empty placeholder doc → reload |
| `get_canvas` | `canvas` | Return current JSON (or empty template) |
| `list_canvases` | — | `{ id, hasContent, updatedAt, title? }[]` |

Optional later: `preview_schema`, `set_canvas_title`.

**Tool design notes for agents:**

- Always replace full `content` (simpler than JSON Patch for LLMs).
- Return validation errors with field paths so the agent can retry once.
- Include `updatedAt` server-side if the agent omits it.

---

## macOS widget structure

Single Widget Extension + `WidgetBundle`:

```swift
@main
struct AgentCanvasBundle: WidgetBundle {
    var body: some Widget {
        CanvasOneWidget()
        CanvasTwoWidget()
        CanvasThreeWidget()
    }
}
```

Each widget:

- Unique `kind` string (`AgentCanvas.one`, etc.)
- Same `CanvasTimelineProvider` + `CanvasView`
- Differs only by which canvas ID / file it loads
- Supports the full set of macOS widget families used in v1

---

## Implementation phases

### Phase 0 — Scaffold

- Repo layout: `schema/`, Rust crates, `platforms/macos` Xcode project
- App Group capability reserved (`group.<bundle-id>.agentcanvas`)
- Three widget kinds + placeholder views (name + family size)
- Golden empty JSON fixtures

### Phase 1 — Storage + timeline

- Rust: validate + read/write canvas files
- Swift: load JSON into timeline entries
- Host: on write (or FSEvents), mirror to App Group if needed + `reloadTimelines`
- Manual test: edit file on disk → widget updates

### Phase 2 — Schema + renderer

- Codable / Rust models aligned with JSON Schema
- `CanvasView` switch on section type
- Component views: header, metrics, chart, list, image, text, spacer
- Dark mode + family-aware layout (collapse charts/lists on small)

### Phase 3 — MCP server

- `agent-canvas-mcp` stdio + HTTP
- Wire tools to core storage + reload hook
- Document Cursor / Claude Desktop snippets
- Show “last updated” in widget chrome

### Phase 4 — Polish

- Empty state: “Drop content here with your agent”
- Malformed JSON → friendly widget message
- Host settings: clear all, open data folder, copy MCP config, daemon status
- Size / validation limits tuned from real agent output

---

## Technical notes & gotchas

1. **WidgetKit budgets** — Prefer full write + `reloadTimelines(ofKind:)` over polling. Expect seconds, not sub-second.
2. **Simulator vs hardware** — Widget update behavior must be verified on a real Mac.
3. **Images** — Cap dimensions/bytes; store under app data when agents send base64; never load arbitrary remote URLs in v1 (sandbox + reliability).
4. **Three kinds vs configuration** — Separate kinds avoid WidgetKit “same kind, different config” pitfalls for agents that need stable addresses.
5. **Sandbox** — MCP child processes ≠ App Group. Design for Application Support + privileged reload path.
6. **Swift Charts** — Supported in modern macOS widgets; still degrade on `systemSmall`.

---

## Success criteria (v1)

1. User can add Canvas One, Two, and Three to the desktop (or Notification Center).
2. Agent calls `update_canvas("one", {…})` and the widget updates within a few seconds while the host is running.
3. Claude / Grok / Cursor produce valid content on the first try against the published schema + tool descriptions.
4. Widgets look native and glanceable at every supported family size.
5. Repo structure and schema do not assume “macOS-only forever.”

---

## Key decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Widget UI | Native WidgetKit (SwiftUI), not Tauri webview | Only way to meet “100% native” on macOS |
| Agent + shared logic | Rust core + MCP | Cross-platform daemon; aligns with remex patterns |
| Host app | Tauri optional; thin is fine | Settings + reload + MCP HTTP; not the glance surface |
| Canvas count | Fixed 3 named slots | Stable agent addressing; zero config |
| Schema | Small, full-document replace | LLM reliability > layout power |
| Storage | App Support JSON + App Group mirror for widgets | External MCP cannot hold App Group entitlements |
| Windows/Linux | Contract now; shells later | Avoid fake cross-platform widgets in v1 |

---

## Open questions (for product owner)

1. **Host packaging:** Prefer Tauri host (shared with remex-style HTTP MCP) vs pure Swift host for a thinner Mac-native install?
2. **Naming / branding:** “Agent Canvas” final, or something shorter for the widget gallery?
3. **Remote images in v1:** Strict local-only, or allow `https://` with size limits?
4. **Monorepo vs new repo:** Stay under `velox/agent-canvas` or spin out when public?

---

## Next step after plan approval

Scaffold Phase 0:

1. JSON Schema + fixtures in `schema/`
2. Rust crate stubs for validate/store/MCP
3. Xcode project stubs: WidgetBundle, three kinds, shared storage reader, Codable schema, TODO renderers

Do **not** start with a Tauri-only widget window prototype if the goal is system widgets — that teaches the wrong architecture.
