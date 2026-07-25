//! Agent Canvas MCP server (stdio).
//!
//! Canvas ids are size-first: sm-one, md-two, lg-three, xl-one, … (12 surfaces).

use std::sync::Arc;
use std::time::Duration;

use agent_canvas_core::{
    default_store, demo_document_kind, density_report, layout_guide_document, matching_ids,
    predict_clip, CanvasCloudClient, CanvasDocument, CanvasId, CanvasSlot, CanvasStore,
    CloudConfig, DemoKind, WidgetSize,
};
use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use clap::{Parser, Subcommand};
use rmcp::{
    handler::server::{router::tool::ToolRouter, wrapper::Parameters},
    model::*,
    schemars, tool, tool_handler, tool_router, ErrorData as McpError, ServerHandler, ServiceExt,
};
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::sync::Mutex;

#[derive(Parser, Debug)]
#[command(name = "agent-canvas-mcp", about = "MCP server for Agent Canvas")]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    /// Override data directory (default: ~/.velox/canvas)
    #[arg(long, global = true)]
    data_dir: Option<std::path::PathBuf>,

    /// Canvas cloud API base URL (default: AGENT_CANVAS_API_URL or https://canvas.velox.test)
    #[arg(long, global = true, env = "AGENT_CANVAS_API_URL")]
    api_url: Option<String>,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Serve MCP over stdio (default when no subcommand)
    Stdio,
    /// Print resolved data directory and canvas paths
    Paths,
    /// Write a sample document to a canvas (dev/debug)
    Seed {
        /// Size-first id, default md-one
        #[arg(default_value = "md-one")]
        canvas: String,
    },
    /// Seed demos. Pick **where** (size/slot) and **what** (content kind).
    ///
    /// Examples:
    ///   seed-demos --size md --content bar
    ///   seed-demos --size lg --slot two --content pie
    ///   seed-demos --content metrics --size all
    ///   seed-demos --content themed --size xl
    SeedDemos {
        /// sm | md | lg | xl | all  (default: all)
        #[arg(long, default_value = "all")]
        size: String,
        /// one | two | three | all  (default: all)
        #[arg(long, default_value = "all")]
        slot: String,
        /// themed | metrics | header | text | list | bar | line | pie | gauge | full
        #[arg(long, default_value = "themed")]
        content: String,
    },
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    let store = match &cli.data_dir {
        Some(p) => CanvasStore::new(p),
        None => default_store(),
    };
    store.ensure_layout()?;

    match cli.command.unwrap_or(Commands::Stdio) {
        Commands::Stdio => serve_stdio(store, cli.api_url.clone()).await?,
        Commands::Paths => {
            println!("data_dir={}", store.root().display());
            println!("canvases_dir={}", store.canvases_dir().display());
            let cloud = match &cli.api_url {
                Some(u) => CloudConfig::parse(u),
                None => CloudConfig::from_env(),
            };
            match cloud {
                Ok(c) => println!("api_url={}", c.api_base),
                Err(e) => println!("api_url=(invalid: {e})"),
            }
            for id in CanvasId::ALL {
                println!(
                    "  {} -> {} (kind={} size={})",
                    id.as_str(),
                    store.path_for(id).display(),
                    id.widget_kind(),
                    id.size.short()
                );
            }
        }
        Commands::Seed { canvas } => {
            let id = CanvasId::parse(&canvas)?;
            let mut doc = CanvasDocument::empty();
            doc.title = Some(format!("{} sample", id.as_str()));
            doc.sections = vec![
                agent_canvas_core::Section::Header {
                    text: format!("Hello ({})", id.as_str()),
                    subtitle: Some(format!(
                        "{} · slot {}",
                        id.size.display_label(),
                        id.slot.as_str()
                    )),
                    priority: None,
                },
                agent_canvas_core::Section::Text {
                    content: format!(
                        "Seed for fixed size {}. Use update_canvas(\"{}\", …).",
                        id.size.short(),
                        id.as_str()
                    ),
                    priority: None,
                },
            ];
            let written = store.write(id, doc)?;
            println!(
                "Wrote {} (updatedAt={})",
                store.path_for(id).display(),
                written.updated_at
            );
            println!("Host running → reload within ~1s; else: just macos-run");
        }
        Commands::SeedDemos {
            size,
            slot,
            content,
        } => {
            let size_f = parse_size_filter(&size)?;
            let slot_f = parse_slot_filter(&slot)?;
            let kind = DemoKind::parse(&content).ok_or_else(|| {
                anyhow::anyhow!(
                    "invalid --content {content:?} (themed|metrics|header|text|list|bar|line|pie|gauge|full)"
                )
            })?;
            let ids = matching_ids(size_f, slot_f);
            if ids.is_empty() {
                anyhow::bail!("no canvases match size={size:?} slot={slot:?}");
            }
            println!(
                "Seeding {} canvas(es) size={} slot={} content={}",
                ids.len(),
                size,
                slot,
                kind.as_str()
            );
            let mut last = String::new();
            for id in ids {
                let doc = demo_document_kind(id, kind);
                let n = doc.sections.len();
                let _written = store.write(id, doc)?;
                last = id.as_str().to_string();
                println!(
                    "  {}  size={} slot={}  kind={}  sections={}",
                    id.as_str(),
                    id.size.short(),
                    id.slot.as_str(),
                    kind.as_str(),
                    n
                );
            }
            if !last.is_empty() {
                let _ = std::fs::write(store.root().join(".reload-request"), format!("{last}\n"));
            }
            println!("Done. Host running → reloads shortly.");
            println!("Tip: just seed-demos md all bar   |   just seed-demos lg two pie");
        }
    }
    Ok(())
}

fn parse_size_filter(s: &str) -> anyhow::Result<Option<WidgetSize>> {
    match s.trim().to_ascii_lowercase().as_str() {
        "all" | "*" => Ok(None),
        other => WidgetSize::parse(other)
            .map(Some)
            .ok_or_else(|| anyhow::anyhow!("invalid --size {s:?} (sm|md|lg|xl|all)")),
    }
}

fn parse_slot_filter(s: &str) -> anyhow::Result<Option<CanvasSlot>> {
    match s.trim().to_ascii_lowercase().as_str() {
        "all" | "*" => Ok(None),
        other => CanvasSlot::parse(other)
            .map(Some)
            .ok_or_else(|| anyhow::anyhow!("invalid --slot {s:?} (one|two|three|all)")),
    }
}

async fn serve_stdio(store: CanvasStore, api_url: Option<String>) -> anyhow::Result<()> {
    let server = AgentCanvasMcp::new(store, api_url)?;
    let service = server
        .serve(rmcp::transport::stdio())
        .await
        .map_err(|e| anyhow::anyhow!("MCP stdio serve failed: {e}"))?;
    service
        .waiting()
        .await
        .map_err(|e| anyhow::anyhow!("MCP stdio wait failed: {e}"))?;
    Ok(())
}

fn json_result(v: Value) -> Result<CallToolResult, McpError> {
    let text = serde_json::to_string_pretty(&v)
        .map_err(|e| McpError::internal_error(e.to_string(), None))?;
    Ok(CallToolResult::success(vec![ContentBlock::text(text)]))
}

fn image_and_json_result(png: &[u8], meta: Value) -> Result<CallToolResult, McpError> {
    let text = serde_json::to_string_pretty(&meta)
        .map_err(|e| McpError::internal_error(e.to_string(), None))?;
    let b64 = B64.encode(png);
    Ok(CallToolResult::success(vec![
        ContentBlock::image(b64, "image/png"),
        ContentBlock::text(text),
    ]))
}

/// Soft tool failure (Claude shows this as tool output, not a generic protocol error).
fn tool_error(v: Value) -> Result<CallToolResult, McpError> {
    let text = serde_json::to_string_pretty(&v)
        .map_err(|e| McpError::internal_error(e.to_string(), None))?;
    Ok(CallToolResult::error(vec![ContentBlock::text(text)]))
}

fn map_err(e: impl std::fmt::Display) -> McpError {
    McpError::invalid_params(e.to_string(), None)
}

/// Append one JSON line under the data dir for post-mortems
/// (Claude's own logs strip tool params as `metadata: undefined`).
fn log_tool_call(store: &CanvasStore, entry: Value) {
    let path = store.root().join("mcp-calls.jsonl");
    let line = match serde_json::to_string(&entry) {
        Ok(s) => s,
        Err(_) => return,
    };
    use std::io::Write;
    if let Ok(mut f) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
    {
        let _ = writeln!(f, "{line}");
    }
}

fn content_shape_summary(raw: &Value) -> Value {
    match raw {
        Value::Object(map) => {
            let keys: Vec<_> = map.keys().cloned().collect();
            let section_types: Vec<String> = map
                .get("sections")
                .and_then(|s| s.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|s| {
                            s.get("type")
                                .and_then(|t| t.as_str())
                                .map(|t| t.to_string())
                        })
                        .collect()
                })
                .unwrap_or_default();
            json!({
                "kind": "object",
                "keys": keys,
                "sectionTypes": section_types,
                "hasVersion": map.contains_key("version"),
            })
        }
        Value::String(s) => json!({ "kind": "string", "len": s.len() }),
        Value::Array(a) => json!({ "kind": "array", "len": a.len() }),
        Value::Null => json!({ "kind": "null" }),
        Value::Bool(_) => json!({ "kind": "bool" }),
        Value::Number(_) => json!({ "kind": "number" }),
    }
}

/// Minimal working document agents copy when inventing content.
const MINIMAL_EXAMPLE: &str = r#"{"version":1,"title":"Hello","sections":[{"type":"header","text":"Hello World","subtitle":"status"},{"type":"metrics","items":[{"label":"Status","value":"OK"}]}]}"#;

/// Accept common agent shapes for `content` (object, JSON string, missing version).
fn parse_canvas_content(raw: Value) -> Result<CanvasDocument, String> {
    let value = match raw {
        Value::String(s) => serde_json::from_str(&s)
            .map_err(|e| format!("content is a string but not valid JSON: {e}"))?,
        Value::Object(_) => raw,
        other => {
            return Err(format!(
                "content must be a JSON object (got {}). Minimal working example: {MINIMAL_EXAMPLE}",
                match other {
                    Value::Null => "null",
                    Value::Bool(_) => "boolean",
                    Value::Number(_) => "number",
                    Value::Array(_) => "array",
                    _ => "unknown",
                }
            ));
        }
    };
    // Inject version if omitted (many models skip it).
    let value = match value {
        Value::Object(mut map) => {
            if !map.contains_key("version") {
                map.insert("version".into(), json!(1));
            }
            if !map.contains_key("sections") {
                if let Some(s) = map.remove("Sections") {
                    map.insert("sections".into(), s);
                }
            }
            // Unwrap accidental double-nesting: { content: { version, sections } }
            if !map.contains_key("sections") {
                if let Some(Value::Object(inner)) = map.remove("content") {
                    map = inner;
                    if !map.contains_key("version") {
                        map.insert("version".into(), json!(1));
                    }
                }
            }
            Value::Object(map)
        }
        other => other,
    };
    serde_json::from_value(value).map_err(|e| {
        format!(
            "invalid content: {e}. Minimal working example: {MINIMAL_EXAMPLE}. \
             Section types: header|text|metrics|chart|list|image|spacer. \
             chartType: bar|line|pie|gauge. metrics items need label+value strings."
        )
    })
}

#[derive(Clone)]
struct AgentCanvasMcp {
    store: Arc<Mutex<CanvasStore>>,
    cloud: Arc<CanvasCloudClient>,
    #[allow(dead_code)]
    tool_router: ToolRouter<Self>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct CanvasArgs {
    /// Size-first id: sm-one | sm-two | sm-three | md-one | … | xl-three
    canvas: String,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct UpdateCanvasArgs {
    /// Size-first id: sm-one | md-two | lg-one | xl-three | …
    canvas: String,
    /// Full canvas document object (NOT a string). Prefer starting from this minimal shape:
    /// {"version":1,"title":"Hello","sections":[{"type":"header","text":"Hello World","subtitle":"status"},{"type":"metrics","items":[{"label":"Status","value":"OK"}]}]}
    /// Section types: header|text|metrics|chart|list|image|spacer. chartType: bar|line|pie|gauge.
    /// metrics items: {label, value, trend?}. list items: {primary, secondary?, badge?}.
    content: Value,
    /// If true, reject over-budget content with repair_hint instead of writing.
    /// Default false: write succeeds but densityReport.overBudget warns; widget still clips.
    #[serde(default)]
    strict: bool,
}

/// Prefer this for simple updates — no full schema inventing required.
#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct UpdateCanvasSimpleArgs {
    /// Size-first id: sm-one | md-two | lg-one | xl-three | …
    canvas: String,
    /// Widget title (optional).
    #[serde(default)]
    title: Option<String>,
    /// Primary header line (required).
    header: String,
    /// Header subtitle (optional).
    #[serde(default)]
    subtitle: Option<String>,
    /// Optional body text under the header.
    #[serde(default)]
    body: Option<String>,
    /// Optional metric value shown as a single glance metric (label defaults to "Status").
    #[serde(default)]
    status: Option<String>,
    /// Optional metric label when `status` is set (default "Status").
    #[serde(default)]
    status_label: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct EmptyArgs {}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct ShareCanvasArgs {
    /// Local size-first canvas id (sm-one, md-one, …).
    canvas: String,
    /// Optional human-readable slug (a-z0-9-). Default: derived from title or canvas id.
    #[serde(default)]
    slug: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct UpdateSharedArgs {
    /// Local canvas id that was previously shared.
    canvas: String,
    /// Optional edit token override (otherwise Keychain / token store).
    #[serde(default)]
    edit_token: Option<String>,
}

#[derive(Debug, Deserialize, schemars::JsonSchema)]
struct UnshareArgs {
    /// Slug or local canvas id of the shared board.
    target: String,
    #[serde(default)]
    edit_token: Option<String>,
}

const ID_HELP: &str =
    "sm-one|sm-two|sm-three|md-one|md-two|md-three|lg-one|lg-two|lg-three|xl-one|xl-two|xl-three";

#[tool_router]
impl AgentCanvasMcp {
    fn new(store: CanvasStore, api_url: Option<String>) -> anyhow::Result<Self> {
        let config = match api_url {
            Some(u) => CloudConfig::parse(&u)?,
            None => CloudConfig::from_env()?,
        };
        let tokens = agent_canvas_core::default_token_store(store.root());
        let cloud = CanvasCloudClient::new(config, store.clone(), tokens)?;
        Ok(Self {
            store: Arc::new(Mutex::new(store)),
            cloud: Arc::new(cloud),
            tool_router: Self::tool_router(),
        })
    }

    #[tool(
        description = "PREFERRED for simple updates (title/header/status text). Builds a valid canvas document for you — use this first when content is simple. \
For charts/lists/full layouts use update_canvas instead. canvas: size-first id (sm-one, md-one, …)."
    )]
    async fn update_canvas_simple(
        &self,
        Parameters(args): Parameters<UpdateCanvasSimpleArgs>,
    ) -> Result<CallToolResult, McpError> {
        let id = match CanvasId::parse(&args.canvas) {
            Ok(id) => id,
            Err(e) => {
                return tool_error(json!({
                    "ok": false,
                    "error": "invalid_canvas_id",
                    "message": e.to_string(),
                    "hint": format!("canvas must be one of: {ID_HELP}"),
                }));
            }
        };

        let mut sections = vec![json!({
            "type": "header",
            "text": args.header,
            "subtitle": args.subtitle,
        })];
        if let Some(body) = args.body.filter(|s| !s.is_empty()) {
            sections.push(json!({ "type": "text", "content": body }));
        }
        if let Some(status) = args.status.filter(|s| !s.is_empty()) {
            let label = args
                .status_label
                .filter(|s| !s.is_empty())
                .unwrap_or_else(|| "Status".into());
            sections.push(json!({
                "type": "metrics",
                "items": [{ "label": label, "value": status }]
            }));
        }

        let content = json!({
            "version": 1,
            "title": args.title.unwrap_or_else(|| args.header.clone()),
            "sections": sections,
        });

        self.write_content(id, content, false).await
    }

    #[tool(
        description = "Replace full content of one desktop canvas with a schema v1 document. \
MINIMAL WORKING content: {\"version\":1,\"title\":\"Hello\",\"sections\":[{\"type\":\"header\",\"text\":\"Hello World\",\"subtitle\":\"status\"},{\"type\":\"metrics\",\"items\":[{\"label\":\"Status\",\"value\":\"OK\"}]}]}. \
canvas is size-first (sm-one, md-two, …). Prefer update_canvas_simple for text/header/status-only updates. \
HARD budgets: sm≤2 sections no charts; md≤4/4/8; lg≤6/8/12; xl≤8/12/20. Full document replace only."
    )]
    async fn update_canvas(
        &self,
        Parameters(args): Parameters<UpdateCanvasArgs>,
    ) -> Result<CallToolResult, McpError> {
        let id = match CanvasId::parse(&args.canvas) {
            Ok(id) => id,
            Err(e) => {
                let store = self.store.lock().await;
                log_tool_call(
                    &store,
                    json!({
                        "ts": chrono::Utc::now().to_rfc3339(),
                        "tool": "update_canvas",
                        "ok": false,
                        "error": "invalid_canvas_id",
                        "canvas": args.canvas,
                        "message": e.to_string(),
                    }),
                );
                return tool_error(json!({
                    "ok": false,
                    "error": "invalid_canvas_id",
                    "message": e.to_string(),
                    "hint": format!("canvas must be one of: {ID_HELP}"),
                }));
            }
        };

        self.write_content(id, args.content, args.strict).await
    }

    async fn write_content(
        &self,
        id: CanvasId,
        content: Value,
        strict: bool,
    ) -> Result<CallToolResult, McpError> {
        let shape = content_shape_summary(&content);
        let doc = match parse_canvas_content(content) {
            Ok(d) => d.normalize_for_write(),
            Err(msg) => {
                let store = self.store.lock().await;
                log_tool_call(
                    &store,
                    json!({
                        "ts": chrono::Utc::now().to_rfc3339(),
                        "tool": "update_canvas",
                        "ok": false,
                        "error": "invalid_content",
                        "canvas": id.as_str(),
                        "contentShape": shape,
                        "message": msg,
                    }),
                );
                return tool_error(json!({
                    "ok": false,
                    "error": "invalid_content",
                    "message": msg,
                    "canvas": id.as_str(),
                    "size": id.size.short(),
                    "contentShape": shape,
                    "example": serde_json::from_str::<Value>(MINIMAL_EXAMPLE).unwrap_or(json!({})),
                    "tip": "Or call update_canvas_simple(canvas, header, status) for simple text/status widgets."
                }));
            }
        };

        if let Err(e) = doc.validate() {
            let store = self.store.lock().await;
            log_tool_call(
                &store,
                json!({
                    "ts": chrono::Utc::now().to_rfc3339(),
                    "tool": "update_canvas",
                    "ok": false,
                    "error": "validation",
                    "canvas": id.as_str(),
                    "message": e.to_string(),
                }),
            );
            return tool_error(json!({
                "ok": false,
                "error": "validation",
                "message": e.to_string(),
                "canvas": id.as_str(),
                "size": id.size.short(),
            }));
        }

        let report = density_report(&doc, id.size);
        let clip = predict_clip(&doc, id.size);

        if strict && report.over_budget {
            return tool_error(json!({
                "ok": false,
                "error": "over_budget",
                "canvas": id.as_str(),
                "size": id.size.short(),
                "densityReport": report,
                "predictedClip": clip,
                "sizeGuide": id.size.guide(),
                "hint": report.repair_hint,
            }));
        }

        let store = self.store.lock().await;
        let written = match store.write(id, doc) {
            Ok(w) => w,
            Err(e) => {
                log_tool_call(
                    &store,
                    json!({
                        "ts": chrono::Utc::now().to_rfc3339(),
                        "tool": "update_canvas",
                        "ok": false,
                        "error": "write_failed",
                        "canvas": id.as_str(),
                        "message": e.to_string(),
                    }),
                );
                return tool_error(json!({
                    "ok": false,
                    "error": "write_failed",
                    "message": e.to_string(),
                    "canvas": id.as_str(),
                }));
            }
        };
        let _ = std::fs::write(
            store.root().join(".reload-request"),
            format!("{}\n{}", id.as_str(), written.updated_at),
        );
        let last_render = store.read_last_render(id);
        log_tool_call(
            &store,
            json!({
                "ts": chrono::Utc::now().to_rfc3339(),
                "tool": "update_canvas",
                "ok": true,
                "canvas": id.as_str(),
                "sections": written.sections.len(),
                "title": written.title,
            }),
        );
        json_result(json!({
            "ok": true,
            "canvas": id.as_str(),
            "size": id.size.short(),
            "slot": id.slot.as_str(),
            "path": store.path_for(id).to_string_lossy(),
            "updatedAt": written.updated_at,
            "widgetKind": id.widget_kind(),
            "sizeGuide": id.size.guide(),
            "densityReport": report,
            "predictedClip": clip,
            "lastRender": last_render,
            "note": "Widget clips to size budget (priority order). Host reloads WidgetKit when running. Use strict=true to fail instead of clip."
        }))
    }

    #[tool(description = "Clear a canvas. canvas: size-first id (sm-one, md-two, …).")]
    async fn clear_canvas(
        &self,
        Parameters(args): Parameters<CanvasArgs>,
    ) -> Result<CallToolResult, McpError> {
        let id = CanvasId::parse(&args.canvas).map_err(map_err)?;
        let store = self.store.lock().await;
        let written = store.clear(id).map_err(map_err)?;
        let _ = std::fs::write(
            store.root().join(".reload-request"),
            format!("{}\n{}", id.as_str(), written.updated_at),
        );
        json_result(json!({
            "ok": true,
            "canvas": id.as_str(),
            "updatedAt": written.updated_at
        }))
    }

    #[tool(
        description = "Get canvas content, sizeGuide, densityReport for current content, and lastRender from the widget (truncated? dropped sections). Use after update_canvas to verify what actually fit."
    )]
    async fn get_canvas(
        &self,
        Parameters(args): Parameters<CanvasArgs>,
    ) -> Result<CallToolResult, McpError> {
        let id = CanvasId::parse(&args.canvas).map_err(map_err)?;
        let store = self.store.lock().await;
        let doc = store.read(id).map_err(map_err)?;
        let report = density_report(&doc, id.size);
        let clip = predict_clip(&doc, id.size);
        let last_render = store.read_last_render(id);
        json_result(json!({
            "canvas": id.as_str(),
            "size": id.size.short(),
            "slot": id.slot.as_str(),
            "content": doc,
            "sizeGuide": id.size.guide(),
            "densityReport": report,
            "predictedClip": clip,
            "lastRender": last_render,
            "tip": "If lastRender.truncated, rewrite with fewer/higher-priority sections for this size."
        }))
    }

    #[tool(
        description = "List all 12 canvases with hasContent, layoutHint, and truncated (from last widget render). Prefer ids the user actually placed."
    )]
    async fn list_canvases(
        &self,
        Parameters(_args): Parameters<EmptyArgs>,
    ) -> Result<CallToolResult, McpError> {
        let store = self.store.lock().await;
        let list = store.list().map_err(map_err)?;
        json_result(json!({
            "canvases": list,
            "idFormat": ID_HELP,
            "budgets": {
                "sm": WidgetSize::Small.budget(),
                "md": WidgetSize::Medium.budget(),
                "lg": WidgetSize::Large.budget(),
                "xl": WidgetSize::ExtraLarge.budget(),
            },
            "tip": "truncated=true means the widget dropped content last time — call get_canvas for lastRender details."
        }))
    }

    #[tool(
        description = "Hard density budgets for sm/md/lg/xl (max sections, list rows, chart points, text chars), section priority defaults, and agent tips. Call before designing dense content."
    )]
    async fn get_layout_guide(
        &self,
        Parameters(_args): Parameters<EmptyArgs>,
    ) -> Result<CallToolResult, McpError> {
        json_result(layout_guide_document())
    }

    #[tool(
        description = "Publish a local canvas to Agent Canvas Cloud (anonymous Phase 1). \
Returns publicUrl + editToken (token also stored in macOS Keychain; shown once — treat as a secret). \
Requires canvas cloud API (AGENT_CANVAS_API_URL). canvas: local id (md-one); optional slug."
    )]
    async fn share_canvas(
        &self,
        Parameters(args): Parameters<ShareCanvasArgs>,
    ) -> Result<CallToolResult, McpError> {
        let id = match CanvasId::parse(&args.canvas) {
            Ok(id) => id,
            Err(e) => {
                return tool_error(json!({
                    "ok": false,
                    "error": "invalid_canvas_id",
                    "message": e.to_string(),
                    "hint": format!("canvas must be one of: {ID_HELP}"),
                }));
            }
        };
        match self.cloud.share_canvas(id, args.slug.as_deref()).await {
            Ok(res) => {
                {
                    let store = self.store.lock().await;
                    log_tool_call(
                        &store,
                        json!({
                            "ts": chrono::Utc::now().to_rfc3339(),
                            "tool": "share_canvas",
                            "ok": true,
                            "canvas": id.as_str(),
                            "slug": res.slug,
                        }),
                    );
                }
                json_result(json!({
                    "ok": true,
                    "canvas": id.as_str(),
                    "slug": res.slug,
                    "publicUrl": res.public_url,
                    "apiUrl": res.api_url,
                    "editToken": res.edit_token,
                    "version": res.version,
                    "etag": res.etag,
                    "note": "editToken is also stored in Keychain (macOS). Others subscribe via publicUrl / GET apiUrl. Keep the token secret.",
                    "apiBase": self.cloud.config().api_base,
                }))
            }
            Err(e) => tool_error(json!({
                "ok": false,
                "error": "share_failed",
                "message": e.to_string(),
                "canvas": id.as_str(),
                "hint": "Is canvas cloud running? Set AGENT_CANVAS_API_URL (default https://canvas.velox.test). Ensure local canvas has content.",
            })),
        }
    }

    #[tool(
        description = "Push the latest local canvas JSON to an already-shared cloud slug (uses stored edit token). \
canvas: local id previously passed to share_canvas."
    )]
    async fn update_shared_canvas(
        &self,
        Parameters(args): Parameters<UpdateSharedArgs>,
    ) -> Result<CallToolResult, McpError> {
        let id = match CanvasId::parse(&args.canvas) {
            Ok(id) => id,
            Err(e) => {
                return tool_error(json!({
                    "ok": false,
                    "error": "invalid_canvas_id",
                    "message": e.to_string(),
                }));
            }
        };
        match self
            .cloud
            .update_shared_canvas(id, args.edit_token.as_deref())
            .await
        {
            Ok(res) => json_result(json!({
                "ok": true,
                "canvas": id.as_str(),
                "slug": res.slug,
                "publicUrl": res.public_url,
                "apiUrl": res.api_url,
                "version": res.version,
                "etag": res.etag,
            })),
            Err(e) => tool_error(json!({
                "ok": false,
                "error": "update_shared_failed",
                "message": e.to_string(),
                "canvas": id.as_str(),
            })),
        }
    }

    #[tool(
        description = "Unpublish a shared canvas (DELETE). target: slug or local canvas id. Clears Keychain edit token."
    )]
    async fn unshare_canvas(
        &self,
        Parameters(args): Parameters<UnshareArgs>,
    ) -> Result<CallToolResult, McpError> {
        match self
            .cloud
            .unshare_canvas(&args.target, args.edit_token.as_deref())
            .await
        {
            Ok(()) => json_result(json!({
                "ok": true,
                "target": args.target,
            })),
            Err(e) => tool_error(json!({
                "ok": false,
                "error": "unshare_failed",
                "message": e.to_string(),
                "target": args.target,
            })),
        }
    }

    #[tool(
        description = "List canvases this machine has published (local share index). Does not list the global cloud directory (none in Phase 1)."
    )]
    async fn list_shared(
        &self,
        Parameters(_args): Parameters<EmptyArgs>,
    ) -> Result<CallToolResult, McpError> {
        match self.cloud.list_shared() {
            Ok(list) => json_result(json!({
                "ok": true,
                "shares": list,
                "apiBase": self.cloud.config().api_base,
            })),
            Err(e) => tool_error(json!({
                "ok": false,
                "error": "list_shared_failed",
                "message": e.to_string(),
            })),
        }
    }

    #[tool(
        description = "Render a PNG snapshot of a canvas using the same SwiftUI view as the live widget (clipping, density, hierarchy). \
Call after update_canvas to verify the design is workable. Requires the Agent Canvas host app running in the menu bar. \
Returns image/png plus JSON meta (truncated, droppedTypes, path). canvas: size-first id (sm-one, md-two, …)."
    )]
    async fn preview_canvas(
        &self,
        Parameters(args): Parameters<CanvasArgs>,
    ) -> Result<CallToolResult, McpError> {
        let id = match CanvasId::parse(&args.canvas) {
            Ok(id) => id,
            Err(e) => {
                return tool_error(json!({
                    "ok": false,
                    "error": "invalid_canvas_id",
                    "message": e.to_string(),
                    "hint": format!("canvas must be one of: {ID_HELP}"),
                }));
            }
        };

        let token = format!(
            "{}-{}",
            chrono::Utc::now().timestamp_millis(),
            std::process::id()
        );

        {
            let store = self.store.lock().await;
            if let Err(e) = store.request_preview(id, &token) {
                return tool_error(json!({
                    "ok": false,
                    "error": "request_failed",
                    "message": e.to_string(),
                    "canvas": id.as_str(),
                }));
            }
            log_tool_call(
                &store,
                json!({
                    "ts": chrono::Utc::now().to_rfc3339(),
                    "tool": "preview_canvas",
                    "phase": "requested",
                    "canvas": id.as_str(),
                    "token": token,
                }),
            );
        }

        // Host polls every ~1s; wait up to ~8s for token match + PNG.
        let deadline = tokio::time::Instant::now() + Duration::from_secs(8);
        loop {
            {
                let store = self.store.lock().await;
                if store.preview_token_matches(id, &token) {
                    let png_path = store.preview_png_path(id);
                    match std::fs::read(&png_path) {
                        Ok(bytes) if !bytes.is_empty() => {
                            let meta = store.read_preview_meta(id).unwrap_or_else(|| {
                                json!({
                                    "ok": true,
                                    "canvas": id.as_str(),
                                    "path": png_path.to_string_lossy(),
                                })
                            });
                            let mut out = meta;
                            if let Some(obj) = out.as_object_mut() {
                                obj.insert("ok".into(), json!(true));
                                obj.insert("canvas".into(), json!(id.as_str()));
                                obj.insert("path".into(), json!(png_path.to_string_lossy()));
                                obj.insert(
                                    "note".into(),
                                    json!("PNG is a host-side snapshot of CanvasView at fixed family size — not a live desktop screencap."),
                                );
                            }
                            log_tool_call(
                                &store,
                                json!({
                                    "ts": chrono::Utc::now().to_rfc3339(),
                                    "tool": "preview_canvas",
                                    "ok": true,
                                    "canvas": id.as_str(),
                                    "bytes": bytes.len(),
                                }),
                            );
                            return image_and_json_result(&bytes, out);
                        }
                        Ok(_) => {
                            // token without bytes yet — keep waiting a bit
                        }
                        Err(_) => {
                            // meta may still report failure
                            if let Some(meta) = store.read_preview_meta(id) {
                                if meta.get("token").and_then(|t| t.as_str())
                                    == Some(token.as_str())
                                    && meta.get("ok") == Some(&json!(false))
                                {
                                    return tool_error(json!({
                                        "ok": false,
                                        "error": "render_failed",
                                        "canvas": id.as_str(),
                                        "meta": meta,
                                        "hint": "Host tried to render but ImageRenderer failed. Ensure Agent Canvas is running (menu bar).",
                                    }));
                                }
                            }
                        }
                    }
                }
            }

            if tokio::time::Instant::now() >= deadline {
                let store = self.store.lock().await;
                log_tool_call(
                    &store,
                    json!({
                        "ts": chrono::Utc::now().to_rfc3339(),
                        "tool": "preview_canvas",
                        "ok": false,
                        "error": "timeout",
                        "canvas": id.as_str(),
                    }),
                );
                return tool_error(json!({
                    "ok": false,
                    "error": "timeout",
                    "canvas": id.as_str(),
                    "path": store.preview_png_path(id).to_string_lossy(),
                    "hint": "Agent Canvas host must be running (menu bar) to render previews. Open the app, then retry preview_canvas. Text-only fallback: get_canvas → lastRender + densityReport.",
                    "dataRoot": store.root().to_string_lossy(),
                }));
            }
            tokio::time::sleep(Duration::from_millis(150)).await;
        }
    }
}

#[tool_handler]
impl ServerHandler for AgentCanvasMcp {
    fn get_info(&self) -> ServerInfo {
        let mut info = ServerInfo::default();
        info.instructions = Some(
            format!(
                "Agent Canvas: 12 fixed-size desktop widgets. Ids: {ID_HELP}. \
                 PREFERRED simple path: update_canvas_simple(canvas=\"sm-one\", header=\"Hello World\", status=\"OK\"). \
                 Full path: update_canvas with content object — minimal example: {MINIMAL_EXAMPLE}. \
                 After updates call preview_canvas(canvas) to get a PNG of the real widget layout (host app must be running). \
                 Cloud publish: share_canvas → publicUrl; update_shared_canvas; unshare_canvas; list_shared \
                 (AGENT_CANVAS_API_URL; edit tokens in Keychain). \
                 Do NOT omit sections[].type. Do NOT send content as a bare string unless it is JSON. \
                 HARD budgets: sm≤2 sections (no charts); md≤4/4/8; lg≤6/8/12; xl≤8/12/20. \
                 If a call fails, read the error JSON (example + tip) and retry once. \
                 Canvas is a glanceable headline, not a document."
            )
        );
        info.capabilities = ServerCapabilities::builder().enable_tools().build();
        info
    }
}
