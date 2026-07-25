//! Local index of shared canvases (no edit tokens — those live in Keychain).

use std::fs;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::error::{Error, Result};
use crate::id::CanvasId;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ShareRecord {
    /// Local widget id that was published (e.g. md-one).
    pub canvas: String,
    pub slug: String,
    pub public_url: String,
    pub api_url: String,
    pub shared_at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_version: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_etag: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct ShareIndexFile {
    #[serde(default)]
    shares: Vec<ShareRecord>,
}

#[derive(Debug, Clone)]
pub struct ShareIndex {
    path: PathBuf,
}

impl ShareIndex {
    pub fn new(data_root: impl AsRef<Path>) -> Self {
        Self {
            path: data_root.as_ref().join("shares.json"),
        }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    fn load(&self) -> Result<ShareIndexFile> {
        if !self.path.exists() {
            return Ok(ShareIndexFile::default());
        }
        let raw = fs::read_to_string(&self.path)?;
        Ok(serde_json::from_str(&raw)?)
    }

    fn save(&self, file: &ShareIndexFile) -> Result<()> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)?;
        }
        let tmp = self.path.with_extension("json.tmp");
        fs::write(&tmp, serde_json::to_string_pretty(file)?)?;
        fs::rename(tmp, &self.path)?;
        Ok(())
    }

    pub fn list(&self) -> Result<Vec<ShareRecord>> {
        Ok(self.load()?.shares)
    }

    pub fn get_by_slug(&self, slug: &str) -> Result<Option<ShareRecord>> {
        Ok(self.load()?.shares.into_iter().find(|s| s.slug == slug))
    }

    pub fn get_by_canvas(&self, canvas: CanvasId) -> Result<Option<ShareRecord>> {
        let key = canvas.as_str();
        Ok(self.load()?.shares.into_iter().find(|s| s.canvas == key))
    }

    pub fn upsert(&self, record: ShareRecord) -> Result<()> {
        let mut file = self.load()?;
        file.shares
            .retain(|s| s.slug != record.slug && s.canvas != record.canvas);
        file.shares.push(record);
        file.shares.sort_by(|a, b| a.slug.cmp(&b.slug));
        self.save(&file)
    }

    pub fn remove_slug(&self, slug: &str) -> Result<bool> {
        let mut file = self.load()?;
        let before = file.shares.len();
        file.shares.retain(|s| s.slug != slug);
        let removed = file.shares.len() != before;
        if removed {
            self.save(&file)?;
        }
        Ok(removed)
    }

    pub fn require_slug(&self, slug: &str) -> Result<ShareRecord> {
        self.get_by_slug(slug)?
            .ok_or_else(|| Error::ShareNotFound(slug.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn upsert_and_list() {
        let dir = tempdir().unwrap();
        let idx = ShareIndex::new(dir.path());
        idx.upsert(ShareRecord {
            canvas: "md-one".into(),
            slug: "demo".into(),
            public_url: "https://example/c/demo".into(),
            api_url: "https://example/api/v1/canvases/demo".into(),
            shared_at: Utc::now(),
            last_version: Some(1),
            last_etag: None,
        })
        .unwrap();
        assert_eq!(idx.list().unwrap().len(), 1);
        idx.remove_slug("demo").unwrap();
        assert!(idx.list().unwrap().is_empty());
    }
}
