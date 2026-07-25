use crate::error::{Error, Result};

/// Base URL for canvas cloud REST (no trailing slash).
///
/// Resolution order:
/// 1. `AGENT_CANVAS_API_URL` env
/// 2. compile-time default for local platform (`https://canvas.velox.test`)
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CloudConfig {
    pub api_base: String,
}

impl CloudConfig {
    pub const ENV_API_URL: &'static str = "AGENT_CANVAS_API_URL";
    pub const DEFAULT_LOCAL: &'static str = "https://canvas.velox.test";
    pub const DEFAULT_PROD: &'static str = "https://canvas.veloxdevworks.com";

    pub fn from_env() -> Result<Self> {
        let raw = std::env::var(Self::ENV_API_URL)
            .ok()
            .filter(|s| !s.trim().is_empty())
            .unwrap_or_else(|| Self::DEFAULT_LOCAL.to_string());
        Self::parse(&raw)
    }

    pub fn parse(raw: &str) -> Result<Self> {
        let s = raw.trim().trim_end_matches('/').to_string();
        if s.is_empty() {
            return Err(Error::CloudConfig("empty AGENT_CANVAS_API_URL".into()));
        }
        if !(s.starts_with("https://") || s.starts_with("http://")) {
            return Err(Error::CloudConfig(format!(
                "AGENT_CANVAS_API_URL must be http(s): got {s}"
            )));
        }
        // Phase 1: prefer https for non-localhost.
        if s.starts_with("http://") {
            let host = s.trim_start_matches("http://");
            let host_only = host.split('/').next().unwrap_or(host);
            let local = host_only.starts_with("127.")
                || host_only.starts_with("localhost")
                || host_only.ends_with(".velox.test")
                || host_only.starts_with("[::1]");
            if !local {
                return Err(Error::CloudConfig(
                    "non-local AGENT_CANVAS_API_URL must use https://".into(),
                ));
            }
        }
        Ok(Self { api_base: s })
    }

    pub fn canvases_url(&self) -> String {
        format!("{}/api/v1/canvases", self.api_base)
    }

    pub fn canvas_url(&self, slug: &str) -> String {
        format!("{}/api/v1/canvases/{slug}", self.api_base)
    }

    /// Public viewer URL (apps/canvas).
    pub fn public_viewer_url(&self, slug: &str) -> String {
        format!("{}/c/{slug}", self.api_base)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_plain_http_remote() {
        assert!(CloudConfig::parse("http://evil.example/api").is_err());
    }

    #[test]
    fn allows_https_and_local_http() {
        assert!(CloudConfig::parse("https://canvas.veloxdevworks.com").is_ok());
        assert!(CloudConfig::parse("http://localhost:4005").is_ok());
        assert!(CloudConfig::parse("https://canvas.velox.test/").is_ok());
    }
}
