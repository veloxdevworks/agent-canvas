//! File-backed canvas storage under `~/.velox/canvas` (cross-process safe).

use std::fs;
use std::path::{Path, PathBuf};

use crate::error::Result;
use crate::history::{self, HistorySource};
use crate::id::CanvasId;
use crate::schema::{CanvasDocument, CanvasSummary, LastRender};

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

    pub fn read(&self, id: CanvasId) -> Result<CanvasDocument> {
        let path = self.path_for(id);
        if !path.exists() {
            return Ok(CanvasDocument::empty());
        }
        let raw = fs::read_to_string(&path)?;
        let doc: CanvasDocument = serde_json::from_str(&raw)?;
        Ok(doc)
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

    pub fn last_render_path(&self, id: CanvasId) -> PathBuf {
        self.canvases_dir()
            .join(format!("{}.render.json", id.as_str()))
    }

    pub fn previews_dir(&self) -> PathBuf {
        self.root.join("previews")
    }

    pub fn preview_png_path(&self, id: CanvasId) -> PathBuf {
        self.previews_dir().join(format!("{}.png", id.as_str()))
    }

    pub fn preview_token_path(&self, id: CanvasId) -> PathBuf {
        self.previews_dir().join(format!("{}.token", id.as_str()))
    }

    pub fn preview_meta_path(&self, id: CanvasId) -> PathBuf {
        self.previews_dir()
            .join(format!("{}.meta.json", id.as_str()))
    }

    pub fn preview_request_path(&self) -> PathBuf {
        self.root.join(".preview-request")
    }

    /// Ask the host app to render a PNG preview. Host watches this file.
    pub fn request_preview(&self, id: CanvasId, token: &str) -> Result<()> {
        self.ensure_layout()?;
        fs::create_dir_all(self.previews_dir())?;
        // Clear prior token so we never accept a stale preview.
        let _ = fs::remove_file(self.preview_token_path(id));
        let body = format!("{}\n{}\n", id.as_str(), token);
        let path = self.preview_request_path();
        let tmp = path.with_extension("request.tmp");
        fs::write(&tmp, body)?;
        fs::rename(&tmp, &path)?;
        Ok(())
    }

    /// True when host has written a matching token for this preview request.
    pub fn preview_token_matches(&self, id: CanvasId, token: &str) -> bool {
        match fs::read_to_string(self.preview_token_path(id)) {
            Ok(s) => s.trim() == token,
            Err(_) => false,
        }
    }

    pub fn read_preview_meta(&self, id: CanvasId) -> Option<serde_json::Value> {
        let raw = fs::read_to_string(self.preview_meta_path(id)).ok()?;
        serde_json::from_str(&raw).ok()
    }

    pub fn read_last_render(&self, id: CanvasId) -> Option<LastRender> {
        let raw = fs::read_to_string(self.last_render_path(id)).ok()?;
        serde_json::from_str(&raw).ok()
    }

    pub fn write_last_render(&self, render: &LastRender) -> Result<()> {
        self.ensure_layout()?;
        // Path is derived from canvas id string already validated by the writer.
        let path = self
            .canvases_dir()
            .join(format!("{}.render.json", render.canvas));
        let tmp = path.with_extension("json.tmp");
        let json = serde_json::to_string_pretty(render)?;
        fs::write(&tmp, json)?;
        fs::rename(&tmp, &path)?;
        Ok(())
    }

    pub fn list(&self) -> Result<Vec<CanvasSummary>> {
        let mut out = Vec::with_capacity(CanvasId::ALL.len());
        for id in CanvasId::ALL {
            let guide = id.size.budget().summary.to_string();
            let truncated = self.read_last_render(id).map(|r| r.truncated);
            let path = self.path_for(id);
            if !path.exists() {
                out.push(CanvasSummary {
                    id: id.as_str().to_string(),
                    size: id.size.short().to_string(),
                    slot: id.slot.as_str().to_string(),
                    has_content: false,
                    updated_at: None,
                    title: None,
                    layout_hint: guide,
                    truncated,
                });
                continue;
            }
            match self.read(id) {
                Ok(doc) => out.push(CanvasSummary {
                    id: id.as_str().to_string(),
                    size: id.size.short().to_string(),
                    slot: id.slot.as_str().to_string(),
                    has_content: !doc.is_empty_content(),
                    updated_at: Some(doc.updated_at),
                    title: doc.title,
                    layout_hint: guide,
                    truncated,
                }),
                Err(_) => out.push(CanvasSummary {
                    id: id.as_str().to_string(),
                    size: id.size.short().to_string(),
                    slot: id.slot.as_str().to_string(),
                    has_content: false,
                    updated_at: None,
                    title: None,
                    layout_hint: guide,
                    truncated,
                }),
            }
        }
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::id::CanvasSlot;
    use crate::layout::WidgetSize;
    use crate::schema::{MetricItem, Section};

    #[test]
    fn roundtrip_write_read() {
        let dir = tempfile_dir();
        let store = CanvasStore::new(&dir);
        let id = CanvasId::new(WidgetSize::Small, CanvasSlot::One);
        let mut doc = CanvasDocument::empty();
        doc.title = Some("Test".into());
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
        store.write(id, doc).unwrap();
        assert!(store.path_for(id).ends_with("sm-one.json"));
        let loaded = store.read(id).unwrap();
        assert_eq!(loaded.title.as_deref(), Some("Test"));
    }

    #[test]
    fn write_archives_previous_and_restore() {
        let dir = tempfile_dir();
        let store = CanvasStore::new(&dir);
        let id = CanvasId::new(WidgetSize::Small, CanvasSlot::Two);
        let mut a = CanvasDocument::empty();
        a.title = Some("First".into());
        a.sections.push(Section::Metrics {
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
        store.write(id, a).unwrap();
        assert!(store.list_history(id).unwrap().is_empty());

        let mut b = CanvasDocument::empty();
        b.title = Some("Second".into());
        b.sections.push(Section::Metrics {
            items: vec![MetricItem {
                label: "A".into(),
                value: "2".into(),
                trend: None,
                icon: None,
                tone: None,
                emphasis: None,
            }],
            priority: None,
        });
        store.write(id, b).unwrap();
        let hist = store.list_history(id).unwrap();
        assert_eq!(hist.len(), 1);
        assert_eq!(hist[0].title.as_deref(), Some("First"));

        let restored = store.restore_history(id, &hist[0].id).unwrap();
        assert_eq!(restored.title.as_deref(), Some("First"));
        // Current "Second" should now be in history.
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
