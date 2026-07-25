//! Edit-token storage. Prefer macOS Keychain; file fallback for Linux CI / agents.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use crate::error::{Error, Result};

const SERVICE: &str = "com.velox.agentcanvas.canvas-edit-token";

pub trait EditTokenStore: Send + Sync {
    fn get(&self, slug: &str) -> Result<Option<String>>;
    fn set(&self, slug: &str, token: &str) -> Result<()>;
    fn delete(&self, slug: &str) -> Result<()>;
}

/// macOS Keychain / platform secret service via `keyring` (PLAT-99).
pub struct KeyringTokenStore;

impl KeyringTokenStore {
    pub fn new() -> Self {
        Self
    }

    fn entry(slug: &str) -> Result<keyring::Entry> {
        keyring::Entry::new(SERVICE, slug).map_err(|e| Error::CredentialStore(e.to_string()))
    }
}

impl Default for KeyringTokenStore {
    fn default() -> Self {
        Self::new()
    }
}

impl EditTokenStore for KeyringTokenStore {
    fn get(&self, slug: &str) -> Result<Option<String>> {
        match Self::entry(slug)?.get_password() {
            Ok(p) if !p.is_empty() => Ok(Some(p)),
            Ok(_) => Ok(None),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(e) => Err(Error::CredentialStore(e.to_string())),
        }
    }

    fn set(&self, slug: &str, token: &str) -> Result<()> {
        Self::entry(slug)?
            .set_password(token)
            .map_err(|e| Error::CredentialStore(e.to_string()))
    }

    fn delete(&self, slug: &str) -> Result<()> {
        match Self::entry(slug)?.delete_credential() {
            Ok(()) => Ok(()),
            Err(keyring::Error::NoEntry) => Ok(()),
            Err(e) => Err(Error::CredentialStore(e.to_string())),
        }
    }
}

/// Restrictive file store under the canvas data root (0600 on Unix).
/// Used for tests (`AGENT_CANVAS_TOKEN_STORE=file`) and non-macOS defaults.
pub struct FileTokenStore {
    dir: PathBuf,
}

impl FileTokenStore {
    pub fn new(dir: impl Into<PathBuf>) -> Result<Self> {
        let dir = dir.into();
        fs::create_dir_all(&dir)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&dir, fs::Permissions::from_mode(0o700));
        }
        Ok(Self { dir })
    }

    fn path(&self, slug: &str) -> PathBuf {
        self.dir.join(format!("{slug}.token"))
    }
}

impl EditTokenStore for FileTokenStore {
    fn get(&self, slug: &str) -> Result<Option<String>> {
        let p = self.path(slug);
        if !p.exists() {
            return Ok(None);
        }
        let s = fs::read_to_string(p)?;
        let t = s.trim();
        if t.is_empty() {
            Ok(None)
        } else {
            Ok(Some(t.to_string()))
        }
    }

    fn set(&self, slug: &str, token: &str) -> Result<()> {
        let p = self.path(slug);
        let tmp = p.with_extension("token.tmp");
        fs::write(&tmp, token)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600));
        }
        fs::rename(tmp, p)?;
        Ok(())
    }

    fn delete(&self, slug: &str) -> Result<()> {
        let p = self.path(slug);
        if p.exists() {
            fs::remove_file(&p)?;
        }
        Ok(())
    }
}

/// Prefer Keychain on macOS; file store elsewhere or when `AGENT_CANVAS_TOKEN_STORE=file`.
pub fn default_token_store(data_root: &Path) -> Arc<dyn EditTokenStore> {
    let force_file = std::env::var("AGENT_CANVAS_TOKEN_STORE")
        .map(|v| v.eq_ignore_ascii_case("file"))
        .unwrap_or(false);
    if force_file {
        return Arc::new(FileTokenStore::new(data_root.join("tokens")).expect("token dir"));
    }
    #[cfg(target_os = "macos")]
    {
        Arc::new(KeyringTokenStore::new())
    }
    #[cfg(not(target_os = "macos"))]
    {
        Arc::new(FileTokenStore::new(data_root.join("tokens")).expect("token dir"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn file_store_roundtrip() {
        let dir = tempdir().unwrap();
        let store = FileTokenStore::new(dir.path()).unwrap();
        assert!(store.get("abc").unwrap().is_none());
        store.set("abc", "secret-token").unwrap();
        assert_eq!(store.get("abc").unwrap().as_deref(), Some("secret-token"));
        store.delete("abc").unwrap();
        assert!(store.get("abc").unwrap().is_none());
    }
}
