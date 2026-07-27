# Privacy

Agent Canvas is designed to keep canvas content **on your Mac** by default.

## What stays local

- Canvas JSON, history, and images under `~/.velox/canvas/` (override with `AGENT_CANVAS_DATA_DIR`)
- Optional MCP call log: `~/.velox/canvas/mcp-calls.jsonl` (tool names, canvas ids, short status — not full image payloads)
- WidgetKit reads the same folder via a sandboxed extension with a home-relative path exception (direct download builds; not Mac App Store)

The menu bar host is **not App Sandboxed** so it can share that folder with the bundled MCP helper that agents spawn.

## What we do not do (v1)

- No analytics or crash telemetry in the app today
- No fetching remote images for canvas content (agents send PNG/JPEG bytes or local `asset:` refs)
- No automatic upload of canvases

## Optional cloud (pre-release)

Cloud publish/subscribe is **off** in Release builds of the host, and MCP share tools require an explicit env/feature gate. When you enable them:

- OAuth access/refresh tokens are stored in your Keychain (`com.velox.agentcanvas.oauth`)
- Per-canvas edit tokens for shared slugs use a separate Keychain service
- Canvas content you choose to share is sent to the API base URL you configure

Disable cloud features and remove Keychain entries if you no longer want that.

## Agent clients

Cursor, Claude Desktop, and other MCP hosts run the bundled `agent-canvas-mcp` helper as a child process. Those products have their own privacy policies for chat content and tool use.

## Contact

Questions: [feedback@veloxdevworks.com](mailto:feedback@veloxdevworks.com)
