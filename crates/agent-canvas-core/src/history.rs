//! Local per-canvas version history under `~/.velox/canvas/history/{id}/`.
//!
//! Layout:
//! ```text
//! history/{canvas-id}/
//!   index.json          # newest-first metadata
//!   {entryId}.json      # full CanvasDocument snapshot
//! ```

use std::fs;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::error::{Error, Result};
use crate::id::CanvasId;
use crate::schema::CanvasDocument;

/// Max retained snapshots per canvas (newest kept).
pub const MAX_HISTORY_ENTRIES: usize = 30;

/// Why a snapshot was taken (best-effort; writers set this).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum HistorySource {
    Mcp,
    Host,
    Restore,
    Clear,
    Seed,
    Cloud,
    #[default]
    Unknown,
}

impl HistorySource {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Mcp => "mcp",
            Self::Host => "host",
            Self::Restore => "restore",
            Self::Clear => "clear",
            Self::Seed => "seed",
            Self::Cloud => "cloud",
            Self::Unknown => "unknown",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryEntryMeta {
    pub id: String,
    pub saved_at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    pub source: HistorySource,
    pub byte_size: u64,
    pub section_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HistoryIndex {
    version: u32,
    entries: Vec<HistoryEntryMeta>,
}

impl HistoryIndex {
    fn empty() -> Self {
        Self {
            version: 1,
            entries: Vec::new(),
        }
    }
}

/// Compare title + sections only (ignore timestamps / schema version churn).
pub fn content_equal(a: &CanvasDocument, b: &CanvasDocument) -> bool {
    a.title == b.title
        && serde_json::to_value(&a.sections).ok() == serde_json::to_value(&b.sections).ok()
}

/// Directory for one canvas's history.
pub fn history_dir(root: &Path, id: CanvasId) -> PathBuf {
    root.join("history").join(id.as_str())
}

fn index_path(dir: &Path) -> PathBuf {
    dir.join("index.json")
}

fn snapshot_path(dir: &Path, entry_id: &str) -> PathBuf {
    dir.join(format!("{entry_id}.json"))
}

fn new_entry_id() -> String {
    let now = Utc::now();
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.subsec_nanos())
        .unwrap_or(0);
    format!("{}-{:06x}", now.format("%Y%m%dT%H%M%SZ"), nanos % 0xFFFFFF)
}

fn load_index(dir: &Path) -> HistoryIndex {
    let path = index_path(dir);
    match fs::read_to_string(&path) {
        Ok(raw) => serde_json::from_str(&raw).unwrap_or_else(|_| rebuild_index(dir)),
        Err(_) => rebuild_index(dir),
    }
}

/// Rebuild index from snapshot files if missing/corrupt.
fn rebuild_index(dir: &Path) -> HistoryIndex {
    let mut entries = Vec::new();
    let Ok(rd) = fs::read_dir(dir) else {
        return HistoryIndex::empty();
    };
    for ent in rd.flatten() {
        let path = ent.path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        let Some(stem) = path.file_stem().and_then(|s| s.to_str()) else {
            continue;
        };
        if stem == "index" {
            continue;
        }
        let Ok(raw) = fs::read_to_string(&path) else {
            continue;
        };
        let Ok(doc) = serde_json::from_str::<CanvasDocument>(&raw) else {
            continue;
        };
        let meta = fs::metadata(&path).ok();
        let saved_at = meta
            .as_ref()
            .and_then(|m| m.modified().ok())
            .and_then(|t| {
                DateTime::<Utc>::from_timestamp(
                    t.duration_since(std::time::UNIX_EPOCH)
                        .ok()?
                        .as_secs() as i64,
                    0,
                )
            })
            .unwrap_or_else(Utc::now);
        entries.push(HistoryEntryMeta {
            id: stem.to_string(),
            saved_at,
            title: doc.title.clone(),
            source: HistorySource::Unknown,
            byte_size: meta.map(|m| m.len()).unwrap_or(raw.len() as u64),
            section_count: doc.sections.len(),
        });
    }
    entries.sort_by(|a, b| b.saved_at.cmp(&a.saved_at).then_with(|| b.id.cmp(&a.id)));
    let idx = HistoryIndex {
        version: 1,
        entries,
    };
    let _ = save_index(dir, &idx);
    idx
}

fn save_index(dir: &Path, index: &HistoryIndex) -> Result<()> {
    fs::create_dir_all(dir)?;
    let path = index_path(dir);
    let tmp = path.with_extension("json.tmp");
    fs::write(&tmp, serde_json::to_string_pretty(index)?)?;
    fs::rename(&tmp, &path)?;
    Ok(())
}

/// Archive `previous` if it differs from `incoming` and is worth keeping.
///
/// Returns `Some(entry_id)` when a snapshot was written.
pub fn archive_if_needed(
    root: &Path,
    id: CanvasId,
    previous: &CanvasDocument,
    incoming: &CanvasDocument,
    source: HistorySource,
) -> Result<Option<String>> {
    // Skip empty→empty and identical content.
    if previous.is_empty_content() && incoming.is_empty_content() {
        return Ok(None);
    }
    if content_equal(previous, incoming) {
        return Ok(None);
    }
    // Nothing useful to archive if previous was empty (first write).
    if previous.is_empty_content() {
        return Ok(None);
    }

    let dir = history_dir(root, id);
    fs::create_dir_all(&dir)?;

    let entry_id = new_entry_id();
    let snap_path = snapshot_path(&dir, &entry_id);
    let json = serde_json::to_string_pretty(previous)?;
    let byte_size = json.len() as u64;
    let tmp = snap_path.with_extension("json.tmp");
    fs::write(&tmp, &json)?;
    fs::rename(&tmp, &snap_path)?;

    let mut index = load_index(&dir);
    index.entries.retain(|e| e.id != entry_id);
    index.entries.insert(
        0,
        HistoryEntryMeta {
            id: entry_id.clone(),
            saved_at: Utc::now(),
            title: previous.title.clone(),
            source,
            byte_size,
            section_count: previous.sections.len(),
        },
    );
    prune_to_cap(&dir, &mut index)?;
    save_index(&dir, &index)?;
    Ok(Some(entry_id))
}

fn prune_to_cap(dir: &Path, index: &mut HistoryIndex) -> Result<()> {
    while index.entries.len() > MAX_HISTORY_ENTRIES {
        if let Some(old) = index.entries.pop() {
            let path = snapshot_path(dir, &old.id);
            let _ = fs::remove_file(path);
        }
    }
    Ok(())
}

/// List history newest-first.
pub fn list(root: &Path, id: CanvasId) -> Result<Vec<HistoryEntryMeta>> {
    let dir = history_dir(root, id);
    if !dir.exists() {
        return Ok(Vec::new());
    }
    Ok(load_index(&dir).entries)
}

/// Load a snapshot document by entry id.
pub fn load(root: &Path, id: CanvasId, entry_id: &str) -> Result<CanvasDocument> {
    let path = snapshot_path(&history_dir(root, id), entry_id);
    if !path.exists() {
        return Err(Error::Validation(format!(
            "history entry not found: {entry_id}"
        )));
    }
    let raw = fs::read_to_string(path)?;
    Ok(serde_json::from_str(&raw)?)
}

/// Delete one history entry (does not change current canvas).
pub fn delete_entry(root: &Path, id: CanvasId, entry_id: &str) -> Result<()> {
    let dir = history_dir(root, id);
    let path = snapshot_path(&dir, entry_id);
    if path.exists() {
        fs::remove_file(&path)?;
    }
    let mut index = load_index(&dir);
    index.entries.retain(|e| e.id != entry_id);
    save_index(&dir, &index)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::id::CanvasSlot;
    use crate::layout::WidgetSize;
    use crate::schema::{MetricItem, Section};

    fn temp_root() -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "agent-canvas-hist-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn sample_doc(title: &str, value: &str) -> CanvasDocument {
        let mut doc = CanvasDocument::empty();
        doc.title = Some(title.into());
        doc.sections.push(Section::Metrics {
            items: vec![MetricItem {
                label: "V".into(),
                value: value.into(),
                trend: None,
            }],
            priority: None,
        });
        doc
    }

    #[test]
    fn archives_on_change_and_lists() {
        let root = temp_root();
        let id = CanvasId::new(WidgetSize::Small, CanvasSlot::One);
        let a = sample_doc("A", "1");
        let b = sample_doc("B", "2");
        let archived = archive_if_needed(&root, id, &a, &b, HistorySource::Mcp)
            .unwrap()
            .expect("should archive");
        let entries = list(&root, id).unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].id, archived);
        assert_eq!(entries[0].title.as_deref(), Some("A"));
        assert_eq!(entries[0].source, HistorySource::Mcp);
        let loaded = load(&root, id, &archived).unwrap();
        assert_eq!(loaded.title.as_deref(), Some("A"));
    }

    #[test]
    fn skips_identical_and_empty() {
        let root = temp_root();
        let id = CanvasId::new(WidgetSize::Small, CanvasSlot::One);
        let a = sample_doc("A", "1");
        assert!(archive_if_needed(&root, id, &a, &a, HistorySource::Host)
            .unwrap()
            .is_none());
        assert!(
            archive_if_needed(
                &root,
                id,
                &CanvasDocument::empty(),
                &CanvasDocument::empty(),
                HistorySource::Clear
            )
            .unwrap()
            .is_none()
        );
        assert!(
            archive_if_needed(
                &root,
                id,
                &CanvasDocument::empty(),
                &a,
                HistorySource::Mcp
            )
            .unwrap()
            .is_none()
        );
        assert!(list(&root, id).unwrap().is_empty());
    }

    #[test]
    fn prunes_to_max() {
        let root = temp_root();
        let id = CanvasId::new(WidgetSize::Medium, CanvasSlot::Two);
        for i in 0..MAX_HISTORY_ENTRIES + 5 {
            let prev = sample_doc("T", &format!("{i}"));
            let next = sample_doc("T", &format!("{}", i + 1));
            archive_if_needed(&root, id, &prev, &next, HistorySource::Mcp).unwrap();
        }
        let entries = list(&root, id).unwrap();
        assert_eq!(entries.len(), MAX_HISTORY_ENTRIES);
        // Snapshot files should match.
        let dir = history_dir(&root, id);
        let snaps = fs::read_dir(&dir)
            .unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| {
                e.path().extension().and_then(|x| x.to_str()) == Some("json")
                    && e.file_name() != "index.json"
            })
            .count();
        assert_eq!(snaps, MAX_HISTORY_ENTRIES);
    }

    #[test]
    fn delete_entry_removes_file() {
        let root = temp_root();
        let id = CanvasId::new(WidgetSize::Large, CanvasSlot::One);
        let a = sample_doc("A", "1");
        let b = sample_doc("B", "2");
        let eid = archive_if_needed(&root, id, &a, &b, HistorySource::Host)
            .unwrap()
            .unwrap();
        delete_entry(&root, id, &eid).unwrap();
        assert!(list(&root, id).unwrap().is_empty());
        assert!(!snapshot_path(&history_dir(&root, id), &eid).exists());
    }
}
