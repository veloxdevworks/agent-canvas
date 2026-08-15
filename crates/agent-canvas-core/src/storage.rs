//! File-backed canvas storage under `~/.velox/canvas` (cross-process safe).
//!
//! Documents live at `canvases/{definition}.json` (`one.json`). Legacy
//! size-baked files (`sm-one.json`, …) are read as aliases for one release.
//! lastRender / preview artifacts are per `(definition, family)` so small and
//! large placements of the same definition do not overwrite each other.

use std::fs;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::error::Result;
use crate::history::{self, HistorySource};
use crate::id::CanvasId;
use crate::layout::WidgetSize;
use crate::schema::{CanvasDocument, CanvasSummary, LastRender};

/// Default density budget when a definition is not placed (medium).
pub const DEFAULT_BUDGET_SIZE: WidgetSize = WidgetSize::Medium;

/// Platform data directory for Agent Canvas JSON files.
///
/// Shared Velox convention: `~/.velox/canvas/`
/// (canvases live in `canvases/`, plus `.reload-request`, `mcp-calls.jsonl`, …).
///
/// Override with `AGENT_CANVAS_DATA_DIR` or MCP `--data-dir`.
pub fn canvas_data_dir() -> PathBuf {
    if let Ok(p) = std::env::var("AGENT_CANVAS_DATA_DIR") {
        if !p.is_empty() {
            return PathBuf::from(p);
        }
    }
    if let Some(home) = directories::BaseDirs::new() {
        return home.home_dir().join(".velox").join("canvas");
    }
    PathBuf::from(".").join(".velox").join("canvas")
}

pub fn default_store() -> CanvasStore {
    CanvasStore::new(canvas_data_dir())
}

/// Host snapshot of WidgetCenter placements (`placed-families.json`).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlacedFamiliesSnapshot {
    #[serde(default)]
    pub version: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<DateTime<Utc>>,
    /// Definition id → placed family shorts (`md`, `lg`, …).
    #[serde(default)]
    pub canvases: std::collections::BTreeMap<String, Vec<String>>,
}

impl PlacedFamiliesSnapshot {
    pub fn families_for(&self, id: CanvasId) -> Vec<WidgetSize> {
        let mut out = Vec::new();
        if let Some(raw) = self.canvases.get(id.as_str()) {
            for s in raw {
                if let Some(size) = WidgetSize::parse(s) {
                    if !out.contains(&size) {
                        out.push(size);
                    }
                }
            }
        }
        out.sort_by_key(|s| WidgetSize::ALL.iter().position(|x| x == s).unwrap_or(99));
        out
    }
}

/// How a density budget size was chosen.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BudgetSource {
    /// Caller passed `size=` (preview / strict / density).
    Requested,
    /// Size-first alias (`sm-one`) supplied a family hint.
    Alias,
    /// WidgetCenter reported this family for the definition.
    Placed,
    /// Unplaced (or unknown); documented default is medium.
    Default,
}

impl BudgetSource {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Requested => "requested",
            Self::Alias => "alias",
            Self::Placed => "placed",
            Self::Default => "default",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ResolvedBudget {
    pub size: WidgetSize,
    pub source: BudgetSource,
}

#[derive(Debug, Clone)]
pub struct CanvasStore {
    root: PathBuf,
}

impl CanvasStore {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn canvases_dir(&self) -> PathBuf {
        self.root.join("canvases")
    }

    /// Canonical document path: `canvases/{definition}.json`.
    pub fn path_for(&self, id: CanvasId) -> PathBuf {
        self.canvases_dir().join(id.file_name())
    }

    pub fn ensure_layout(&self) -> Result<()> {
        fs::create_dir_all(self.canvases_dir())?;
        fs::create_dir_all(self.previews_dir())?;
        fs::create_dir_all(self.root.join("history"))?;
        fs::create_dir_all(crate::assets::assets_dir(&self.root))?;
        Ok(())
    }

    pub fn assets_dir(&self) -> PathBuf {
        crate::assets::assets_dir(&self.root)
    }

    /// Resolve which file to read for a definition.
    ///
    /// 1. Canonical `one.json` if it exists (even when empty).
    /// 2. Else legacy aliases `sm-one.json` … `xl-one.json`:
    ///    prefer a **non-empty** `md-*`, else the first non-empty in
    ///    sm → md → lg → xl order. Conflicting alias files are never merged.
    pub fn resolve_read_path(&self, id: CanvasId) -> Option<PathBuf> {
        let canonical = self.path_for(id);
        if canonical.exists() {
            return Some(canonical);
        }
        let mut md_nonempty: Option<PathBuf> = None;
        let mut first_nonempty: Option<PathBuf> = None;
        for name in id.legacy_file_names() {
            let path = self.canvases_dir().join(name);
            if !path.exists() {
                continue;
            }
            let nonempty = read_doc_file(&path)
                .map(|d| !d.is_empty_content())
                .unwrap_or(false);
            if nonempty && first_nonempty.is_none() {
                first_nonempty = Some(path.clone());
            }
            if nonempty && name.starts_with("md-") {
                md_nonempty = Some(path);
            }
        }
        md_nonempty.or(first_nonempty)
    }

    pub fn read(&self, id: CanvasId) -> Result<CanvasDocument> {
        match self.resolve_read_path(id) {
            None => Ok(CanvasDocument::empty()),
            Some(path) => Ok(read_doc_file(&path).unwrap_or_else(|_| CanvasDocument::empty())),
        }
    }

    /// Write canvas JSON, archiving the previous version when content changes.
    pub fn write(&self, id: CanvasId, doc: CanvasDocument) -> Result<CanvasDocument> {
        self.write_with_source(id, doc, HistorySource::Mcp)
    }

    /// Write with an explicit history source tag.
    pub fn write_with_source(
        &self,
        id: CanvasId,
        doc: CanvasDocument,
        source: HistorySource,
    ) -> Result<CanvasDocument> {
        self.ensure_layout()?;
        let previous = self.read(id)?;
        let doc = doc.normalize_for_write();
        // Externalize data: URLs → asset: refs before validate/archive/write.
        let doc = crate::assets::externalize_document(self.root(), doc)?;
        doc.validate()?;
        // Archive the *previous* content before overwriting (source describes this write).
        let _ = history::archive_if_needed(self.root(), id, &previous, &doc, source)?;
        let path = self.path_for(id);
        let tmp = path.with_extension("json.tmp");
        let json = serde_json::to_string_pretty(&doc)?;
        fs::write(&tmp, json)?;
        fs::rename(&tmp, &path)?;
        // Best-effort sweep of unreferenced assets after a successful write.
        let _ = crate::assets::gc(self.root());
        Ok(doc)
    }

    pub fn clear(&self, id: CanvasId) -> Result<CanvasDocument> {
        self.write_with_source(id, CanvasDocument::empty(), HistorySource::Clear)
    }

    /// Restore a history entry as the current canvas (archives current first).
    pub fn restore_history(&self, id: CanvasId, entry_id: &str) -> Result<CanvasDocument> {
        let snap = history::load(self.root(), id, entry_id)?;
        self.write_with_source(id, snap, HistorySource::Restore)
    }

    pub fn list_history(&self, id: CanvasId) -> Result<Vec<history::HistoryEntryMeta>> {
        history::list(self.root(), id)
    }

    pub fn delete_history_entry(&self, id: CanvasId, entry_id: &str) -> Result<()> {
        history::delete_entry(self.root(), id, entry_id)
    }

    pub fn last_render_path(&self, id: CanvasId, size: WidgetSize) -> PathBuf {
        self.canvases_dir()
            .join(format!("{}.{}.render.json", id.as_str(), size.short()))
    }

    pub fn previews_dir(&self) -> PathBuf {
        self.root.join("previews")
    }

    fn preview_stem(id: CanvasId, size: WidgetSize) -> String {
        format!("{}.{}", id.as_str(), size.short())
    }

    pub fn preview_png_path(&self, id: CanvasId, size: WidgetSize) -> PathBuf {
        self.previews_dir()
            .join(format!("{}.png", Self::preview_stem(id, size)))
    }

    pub fn preview_token_path(&self, id: CanvasId, size: WidgetSize) -> PathBuf {
        self.previews_dir()
            .join(format!("{}.token", Self::preview_stem(id, size)))
    }

    pub fn preview_meta_path(&self, id: CanvasId, size: WidgetSize) -> PathBuf {
        self.previews_dir()
            .join(format!("{}.meta.json", Self::preview_stem(id, size)))
    }

    pub fn preview_request_path(&self) -> PathBuf {
        self.root.join(".preview-request")
    }

    pub fn placed_families_path(&self) -> PathBuf {
        self.root.join("placed-families.json")
    }

    pub fn read_placed_families(&self) -> PlacedFamiliesSnapshot {
        let raw = fs::read_to_string(self.placed_families_path()).ok();
        raw.and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    }

    pub fn write_placed_families(&self, snap: &PlacedFamiliesSnapshot) -> Result<()> {
        self.ensure_layout()?;
        let path = self.placed_families_path();
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, serde_json::to_string_pretty(snap)?)?;
        fs::rename(&tmp, &path)?;
        Ok(())
    }

    /// Resolve the family used for density / preview / strict.
    ///
    /// Order: explicit `size` → unique placed family → alias size → default medium.
    /// Multiple placed families: still default to medium unless `size` is passed
    /// (MCP reports every placed family on `list_canvases`).
    pub fn resolve_budget(
        &self,
        id: CanvasId,
        requested: Option<WidgetSize>,
        alias_size: Option<WidgetSize>,
    ) -> ResolvedBudget {
        if let Some(size) = requested {
            return ResolvedBudget {
                size,
                source: BudgetSource::Requested,
            };
        }
        let placed = self.read_placed_families().families_for(id);
        if placed.len() == 1 {
            return ResolvedBudget {
                size: placed[0],
                source: BudgetSource::Placed,
            };
        }
        if let Some(size) = alias_size {
            return ResolvedBudget {
                size,
                source: BudgetSource::Alias,
            };
        }
        if placed.is_empty() {
            ResolvedBudget {
                size: DEFAULT_BUDGET_SIZE,
                source: BudgetSource::Default,
            }
        } else if placed.contains(&DEFAULT_BUDGET_SIZE) {
            ResolvedBudget {
                size: DEFAULT_BUDGET_SIZE,
                source: BudgetSource::Placed,
            }
        } else {
            ResolvedBudget {
                size: placed[0],
                source: BudgetSource::Placed,
            }
        }
    }

    /// Ask the host app to render a PNG preview. Host watches this file.
    ///
    /// Body:
    /// ```text
    /// {definition}
    /// {token}
    /// {size}   # sm|md|lg|xl
    /// ```
    pub fn request_preview(&self, id: CanvasId, size: WidgetSize, token: &str) -> Result<()> {
        self.ensure_layout()?;
        fs::create_dir_all(self.previews_dir())?;
        // Clear prior token so we never accept a stale preview.
        let _ = fs::remove_file(self.preview_token_path(id, size));
        let body = format!("{}\n{}\n{}\n", id.as_str(), token, size.short());
        let path = self.preview_request_path();
        let tmp = path.with_extension("request.tmp");
        fs::write(&tmp, body)?;
        fs::rename(&tmp, &path)?;
        Ok(())
    }

    /// True when host has written a matching token for this preview request.
    pub fn preview_token_matches(&self, id: CanvasId, size: WidgetSize, token: &str) -> bool {
        match fs::read_to_string(self.preview_token_path(id, size)) {
            Ok(s) => s.trim() == token,
            Err(_) => false,
        }
    }

    pub fn read_preview_meta(&self, id: CanvasId, size: WidgetSize) -> Option<serde_json::Value> {
        let raw = fs::read_to_string(self.preview_meta_path(id, size)).ok()?;
        serde_json::from_str(&raw).ok()
    }

    pub fn read_last_render(&self, id: CanvasId, size: WidgetSize) -> Option<LastRender> {
        let raw = fs::read_to_string(self.last_render_path(id, size)).ok()?;
        serde_json::from_str(&raw).ok()
    }

    pub fn read_last_renders(&self, id: CanvasId) -> Vec<LastRender> {
        WidgetSize::ALL
            .into_iter()
            .filter_map(|size| self.read_last_render(id, size))
            .collect()
    }

    pub fn write_last_render(&self, render: &LastRender) -> Result<()> {
        self.ensure_layout()?;
        let id = CanvasId::parse(&render.canvas)?;
        let size = WidgetSize::parse(&render.size).unwrap_or(DEFAULT_BUDGET_SIZE);
        let path = self.last_render_path(id, size);
        let tmp = path.with_extension("json.tmp");
        let json = serde_json::to_string_pretty(render)?;
        fs::write(&tmp, json)?;
        fs::rename(&tmp, &path)?;
        Ok(())
    }

    pub fn list(&self) -> Result<Vec<CanvasSummary>> {
        let placed = self.read_placed_families();
        let mut out = Vec::with_capacity(CanvasId::ALL.len());
        for id in CanvasId::ALL {
            let families = placed.families_for(id);
            let budget = self.resolve_budget(id, None, None);
            let guide = budget.size.budget().summary.to_string();
            let last_renders = self.read_last_renders(id);
            let truncated = self.read_last_render(id, budget.size).map(|r| r.truncated);
            let placed_families: Vec<String> =
                families.iter().map(|s| s.short().to_string()).collect();
            let budget_source = if families.is_empty() {
                BudgetSource::Default.as_str().to_string()
            } else {
                BudgetSource::Placed.as_str().to_string()
            };

            match self.read(id) {
                Ok(doc) => out.push(CanvasSummary {
                    id: id.as_str().to_string(),
                    slot: id.slot.as_str().to_string(),
                    has_content: !doc.is_empty_content(),
                    updated_at: if doc.is_empty_content() && self.resolve_read_path(id).is_none() {
                        None
                    } else {
                        Some(doc.updated_at)
                    },
                    title: doc.title,
                    placed_families,
                    budget_size: budget.size.short().to_string(),
                    budget_source,
                    layout_hint: guide,
                    truncated,
                    last_renders,
                }),
                Err(_) => out.push(CanvasSummary {
                    id: id.as_str().to_string(),
                    slot: id.slot.as_str().to_string(),
                    has_content: false,
                    updated_at: None,
                    title: None,
                    placed_families,
                    budget_size: budget.size.short().to_string(),
                    budget_source,
                    layout_hint: guide,
                    truncated,
                    last_renders,
                }),
            }
        }
        Ok(out)
    }
}

fn read_doc_file(path: &Path) -> Result<CanvasDocument> {
    let raw = fs::read_to_string(path)?;
    Ok(serde_json::from_str(&raw)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::id::CanvasSlot;
    use crate::schema::{MetricItem, Section};

    fn nonempty_doc(title: &str) -> CanvasDocument {
        let mut doc = CanvasDocument::empty();
        doc.title = Some(title.into());
        doc.sections.push(Section::Metrics {
            items: vec![MetricItem {
                label: "A".into(),
                value: "1".into(),
                trend: None,
                icon: None,
                tone: None,
                emphasis: None,
            }],
            priority: None,
        });
        doc
    }

    #[test]
    fn roundtrip_write_read_canonical() {
        let dir = tempfile_dir();
        let store = CanvasStore::new(&dir);
        let id = CanvasId::new(CanvasSlot::One);
        store.write(id, nonempty_doc("Test")).unwrap();
        assert!(store.path_for(id).ends_with("one.json"));
        let loaded = store.read(id).unwrap();
        assert_eq!(loaded.title.as_deref(), Some("Test"));
    }

    #[test]
    fn alias_prefers_nonempty_md() {
        let dir = tempfile_dir();
        let store = CanvasStore::new(&dir);
        store.ensure_layout().unwrap();
        let canvases = store.canvases_dir();
        fs::write(
            canvases.join("sm-one.json"),
            serde_json::to_string(&nonempty_doc("small")).unwrap(),
        )
        .unwrap();
        fs::write(
            canvases.join("md-one.json"),
            serde_json::to_string(&nonempty_doc("medium")).unwrap(),
        )
        .unwrap();
        let loaded = store.read(CanvasId::new(CanvasSlot::One)).unwrap();
        assert_eq!(loaded.title.as_deref(), Some("medium"));
    }

    #[test]
    fn alias_first_nonempty_when_md_empty() {
        let dir = tempfile_dir();
        let store = CanvasStore::new(&dir);
        store.ensure_layout().unwrap();
        let canvases = store.canvases_dir();
        fs::write(
            canvases.join("sm-one.json"),
            serde_json::to_string(&nonempty_doc("small")).unwrap(),
        )
        .unwrap();
        fs::write(
            canvases.join("md-one.json"),
            serde_json::to_string(&CanvasDocument::empty()).unwrap(),
        )
        .unwrap();
        let loaded = store.read(CanvasId::new(CanvasSlot::One)).unwrap();
        assert_eq!(loaded.title.as_deref(), Some("small"));
    }

    #[test]
    fn canonical_wins_over_aliases() {
        let dir = tempfile_dir();
        let store = CanvasStore::new(&dir);
        let id = CanvasId::new(CanvasSlot::One);
        store.write(id, nonempty_doc("canonical")).unwrap();
        fs::write(
            store.canvases_dir().join("md-one.json"),
            serde_json::to_string(&nonempty_doc("alias")).unwrap(),
        )
        .unwrap();
        let loaded = store.read(id).unwrap();
        assert_eq!(loaded.title.as_deref(), Some("canonical"));
    }

    #[test]
    fn last_render_is_per_family() {
        let dir = tempfile_dir();
        let store = CanvasStore::new(&dir);
        let id = CanvasId::new(CanvasSlot::One);
        let sm = LastRender {
            canvas: "one".into(),
            size: "sm".into(),
            truncated: true,
            shown_section_count: 1,
            dropped_section_count: 2,
            dropped_types: vec!["text".into()],
            list_items_shown: 0,
            list_items_total: 0,
            updated_at: Utc::now(),
        };
        let md = LastRender {
            canvas: "one".into(),
            size: "md".into(),
            truncated: false,
            shown_section_count: 3,
            dropped_section_count: 0,
            dropped_types: vec![],
            list_items_shown: 2,
            list_items_total: 2,
            updated_at: Utc::now(),
        };
        store.write_last_render(&sm).unwrap();
        store.write_last_render(&md).unwrap();
        assert!(
            store
                .read_last_render(id, WidgetSize::Small)
                .unwrap()
                .truncated
        );
        assert!(
            !store
                .read_last_render(id, WidgetSize::Medium)
                .unwrap()
                .truncated
        );
        assert_eq!(store.read_last_renders(id).len(), 2);
    }

    #[test]
    fn list_includes_placed_families() {
        let dir = tempfile_dir();
        let store = CanvasStore::new(&dir);
        let id = CanvasId::new(CanvasSlot::Two);
        store.write(id, nonempty_doc("Board")).unwrap();
        let mut snap = PlacedFamiliesSnapshot::default();
        snap.canvases
            .insert("two".into(), vec!["lg".into(), "sm".into()]);
        store.write_placed_families(&snap).unwrap();
        let list = store.list().unwrap();
        assert_eq!(list.len(), 12);
        let two = list.iter().find(|c| c.id == "two").unwrap();
        assert_eq!(two.placed_families, vec!["sm", "lg"]);
        assert_eq!(two.budget_source, "placed");
        assert!(two.has_content);
        let one = list.iter().find(|c| c.id == "one").unwrap();
        assert!(one.placed_families.is_empty());
        assert_eq!(one.budget_source, "default");
        assert_eq!(one.budget_size, "md");
    }

    #[test]
    fn write_archives_previous_and_restore() {
        let dir = tempfile_dir();
        let store = CanvasStore::new(&dir);
        let id = CanvasId::new(CanvasSlot::Two);
        store.write(id, nonempty_doc("First")).unwrap();
        assert!(store.list_history(id).unwrap().is_empty());

        store.write(id, nonempty_doc("Second")).unwrap();
        let hist = store.list_history(id).unwrap();
        assert_eq!(hist.len(), 1);
        assert_eq!(hist[0].title.as_deref(), Some("First"));

        let restored = store.restore_history(id, &hist[0].id).unwrap();
        assert_eq!(restored.title.as_deref(), Some("First"));
        let hist2 = store.list_history(id).unwrap();
        assert!(hist2.iter().any(|e| e.title.as_deref() == Some("Second")));
    }

    fn tempfile_dir() -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "agent-canvas-test-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }
}
