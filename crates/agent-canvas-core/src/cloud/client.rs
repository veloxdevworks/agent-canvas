//! HTTP client for canvas cloud REST (PLAT-97).

use std::sync::Arc;
use std::time::Duration;

use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::config::CloudConfig;
use super::credentials::EditTokenStore;
use super::share_index::{ShareIndex, ShareRecord};
use super::slug::{normalize_slug, validate_slug};
use crate::error::{Error, Result};
use crate::id::CanvasId;
use crate::schema::CanvasDocument;
use crate::storage::CanvasStore;

const EDIT_TOKEN_HEADER: &str = "X-Canvas-Edit-Token";
const MAX_BODY_BYTES: usize = 64 * 1024;

#[derive(Clone)]
pub struct CanvasCloudClient {
    config: CloudConfig,
    http: reqwest::Client,
    pub(crate) tokens: Arc<dyn EditTokenStore>,
    shares: ShareIndex,
    store: CanvasStore,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PublishResponse {
    pub slug: String,
    pub public_url: String,
    pub api_url: String,
    /// Present only on create (returned once).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub edit_token: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub version: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub etag: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateSharedResponse {
    pub slug: String,
    pub public_url: String,
    pub api_url: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub version: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub etag: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SharedCanvasInfo {
    pub canvas: String,
    pub slug: String,
    pub public_url: String,
    pub api_url: String,
    pub shared_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_version: Option<u32>,
    pub has_edit_token: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct PublishBody<'a> {
    #[serde(skip_serializing_if = "Option::is_none")]
    slug: Option<&'a str>,
    document: &'a CanvasDocument,
}

impl CanvasCloudClient {
    pub fn new(
        config: CloudConfig,
        store: CanvasStore,
        tokens: Arc<dyn EditTokenStore>,
    ) -> Result<Self> {
        let http = reqwest::Client::builder()
            .timeout(Duration::from_secs(30))
            .user_agent(format!("agent-canvas-mcp/{}", env!("CARGO_PKG_VERSION")))
            .build()
            .map_err(|e| Error::CloudTransport(e.to_string()))?;
        let shares = ShareIndex::new(store.root());
        Ok(Self {
            config,
            http,
            tokens,
            shares,
            store,
        })
    }

    pub fn from_env(store: CanvasStore) -> Result<Self> {
        let config = CloudConfig::from_env()?;
        let tokens = super::credentials::default_token_store(store.root());
        Self::new(config, store, tokens)
    }

    pub fn config(&self) -> &CloudConfig {
        &self.config
    }

    pub fn shares(&self) -> &ShareIndex {
        &self.shares
    }

    /// Publish local canvas slot to cloud. Returns edit token only on success (create).
    pub async fn share_canvas(
        &self,
        canvas: CanvasId,
        slug: Option<&str>,
    ) -> Result<PublishResponse> {
        let doc = self.store.read(canvas)?;
        if doc.is_empty_content() {
            return Err(Error::Validation(
                "canvas is empty — update_canvas before share_canvas".into(),
            ));
        }
        doc.validate()?;
        let body_json = serde_json::to_vec(&doc)?;
        if body_json.len() > MAX_BODY_BYTES {
            return Err(Error::Validation(format!(
                "document exceeds {MAX_BODY_BYTES} byte cloud limit"
            )));
        }

        let slug_owned = match slug {
            Some(s) => {
                validate_slug(s)?;
                s.to_string()
            }
            None => {
                let hint = doc
                    .title
                    .as_deref()
                    .filter(|t| !t.is_empty())
                    .unwrap_or(canvas.as_str());
                normalize_slug(hint).unwrap_or_else(|_| format!("{}-board", canvas.size.short()))
            }
        };

        let payload = PublishBody {
            slug: Some(slug_owned.as_str()),
            document: &doc,
        };

        let res = self
            .http
            .post(self.config.canvases_url())
            .json(&payload)
            .send()
            .await
            .map_err(|e| Error::CloudTransport(e.to_string()))?;

        let status = res.status();
        let etag = res
            .headers()
            .get("etag")
            .and_then(|v| v.to_str().ok())
            .map(|s| s.trim_matches('"').to_string());
        let text = res
            .text()
            .await
            .map_err(|e| Error::CloudTransport(e.to_string()))?;

        if !status.is_success() {
            return Err(Error::CloudHttp {
                status: status.as_u16(),
                message: truncate(&text, 500),
            });
        }

        let mut parsed: PublishResponse = serde_json::from_str(&text).unwrap_or(PublishResponse {
            slug: slug_owned.clone(),
            public_url: self.config.public_viewer_url(&slug_owned),
            api_url: self.config.canvas_url(&slug_owned),
            edit_token: None,
            version: Some(1),
            etag: etag.clone(),
        });

        // Normalize URLs if server omitted them.
        if parsed.public_url.is_empty() {
            parsed.public_url = self.config.public_viewer_url(&parsed.slug);
        }
        if parsed.api_url.is_empty() {
            parsed.api_url = self.config.canvas_url(&parsed.slug);
        }
        if parsed.etag.is_none() {
            parsed.etag = etag;
        }

        // Extract edit token from flexible response shapes.
        if parsed.edit_token.is_none() {
            if let Ok(v) = serde_json::from_str::<Value>(&text) {
                parsed.edit_token = v
                    .get("editToken")
                    .or_else(|| v.get("edit_token"))
                    .or_else(|| v.get("token"))
                    .and_then(|t| t.as_str())
                    .map(|s| s.to_string());
            }
        }

        if let Some(token) = &parsed.edit_token {
            self.tokens.set(&parsed.slug, token)?;
        }

        self.shares.upsert(ShareRecord {
            canvas: canvas.as_str().to_string(),
            slug: parsed.slug.clone(),
            public_url: parsed.public_url.clone(),
            api_url: parsed.api_url.clone(),
            shared_at: Utc::now(),
            last_version: parsed.version,
            last_etag: parsed.etag.clone(),
        })?;

        Ok(parsed)
    }

    pub async fn update_shared_canvas(
        &self,
        canvas: CanvasId,
        edit_token: Option<&str>,
    ) -> Result<UpdateSharedResponse> {
        let record = self
            .shares
            .get_by_canvas(canvas)?
            .ok_or_else(|| Error::ShareNotFound(canvas.as_str().into()))?;
        let token = match edit_token {
            Some(t) if !t.is_empty() => t.to_string(),
            _ => self
                .tokens
                .get(&record.slug)?
                .ok_or_else(|| Error::MissingEditToken(record.slug.clone()))?,
        };

        let doc = self.store.read(canvas)?;
        if doc.is_empty_content() {
            return Err(Error::Validation(
                "canvas is empty — nothing to push".into(),
            ));
        }
        doc.validate()?;

        let payload = PublishBody {
            slug: None,
            document: &doc,
        };

        let res = self
            .http
            .put(self.config.canvas_url(&record.slug))
            .header(EDIT_TOKEN_HEADER, &token)
            .json(&payload)
            .send()
            .await
            .map_err(|e| Error::CloudTransport(e.to_string()))?;

        let status = res.status();
        let etag = res
            .headers()
            .get("etag")
            .and_then(|v| v.to_str().ok())
            .map(|s| s.trim_matches('"').to_string());
        let text = res
            .text()
            .await
            .map_err(|e| Error::CloudTransport(e.to_string()))?;

        if !status.is_success() {
            return Err(Error::CloudHttp {
                status: status.as_u16(),
                message: truncate(&text, 500),
            });
        }

        let version = serde_json::from_str::<Value>(&text)
            .ok()
            .and_then(|v| v.get("version").and_then(|x| x.as_u64()).map(|n| n as u32));

        let mut updated = record.clone();
        updated.last_version = version.or(record.last_version.map(|v| v.saturating_add(1)));
        updated.last_etag = etag.clone().or(record.last_etag);
        self.shares.upsert(updated.clone())?;

        // Persist token if caller supplied a new one.
        if edit_token.is_some() {
            self.tokens.set(&record.slug, &token)?;
        }

        Ok(UpdateSharedResponse {
            slug: record.slug,
            public_url: record.public_url,
            api_url: record.api_url,
            version: updated.last_version,
            etag,
        })
    }

    pub async fn unshare_canvas(
        &self,
        slug_or_canvas: &str,
        edit_token: Option<&str>,
    ) -> Result<()> {
        let record = if let Ok(id) = CanvasId::parse(slug_or_canvas) {
            self.shares
                .get_by_canvas(id)?
                .ok_or_else(|| Error::ShareNotFound(slug_or_canvas.into()))?
        } else {
            validate_slug(slug_or_canvas)?;
            self.shares.require_slug(slug_or_canvas)?
        };

        let token = match edit_token {
            Some(t) if !t.is_empty() => t.to_string(),
            _ => self
                .tokens
                .get(&record.slug)?
                .ok_or_else(|| Error::MissingEditToken(record.slug.clone()))?,
        };

        let res = self
            .http
            .delete(self.config.canvas_url(&record.slug))
            .header(EDIT_TOKEN_HEADER, &token)
            .send()
            .await
            .map_err(|e| Error::CloudTransport(e.to_string()))?;

        let status = res.status();
        let text = res
            .text()
            .await
            .map_err(|e| Error::CloudTransport(e.to_string()))?;

        // 404/410: already gone — still clear local state.
        if !status.is_success() && status.as_u16() != 404 && status.as_u16() != 410 {
            return Err(Error::CloudHttp {
                status: status.as_u16(),
                message: truncate(&text, 500),
            });
        }

        let _ = self.tokens.delete(&record.slug);
        let _ = self.shares.remove_slug(&record.slug);
        Ok(())
    }

    pub fn list_shared(&self) -> Result<Vec<SharedCanvasInfo>> {
        let mut out = Vec::new();
        for r in self.shares.list()? {
            let has = self.tokens.get(&r.slug)?.is_some();
            out.push(SharedCanvasInfo {
                canvas: r.canvas,
                slug: r.slug,
                public_url: r.public_url,
                api_url: r.api_url,
                shared_at: r.shared_at.to_rfc3339(),
                last_version: r.last_version,
                has_edit_token: has,
            });
        }
        Ok(out)
    }
}

fn truncate(s: &str, max: usize) -> String {
    if s.len() <= max {
        s.to_string()
    } else {
        format!("{}…", &s[..max])
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cloud::credentials::FileTokenStore;
    use crate::schema::{MetricItem, Section};
    use crate::storage::CanvasStore;
    use tempfile::tempdir;
    use wiremock::matchers::{header, method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    async fn setup() -> (MockServer, CanvasCloudClient, CanvasId, tempfile::TempDir) {
        let server = MockServer::start().await;
        let dir = tempdir().unwrap();
        let store = CanvasStore::new(dir.path());
        store.ensure_layout().unwrap();
        let id = CanvasId::parse("md-one").unwrap();
        let mut doc = CanvasDocument::empty();
        doc.title = Some("Demo".into());
        doc.sections.push(Section::Header {
            text: "Hello".into(),
            subtitle: None,
            tone: None,
            emphasis: None,
            priority: None,
        });
        doc.sections.push(Section::Metrics {
            items: vec![MetricItem {
                label: "Status".into(),
                value: "OK".into(),
                trend: None,
                tone: None,
                emphasis: None,
            
            }],
            priority: None,
        });
        store.write(id, doc).unwrap();

        let config = CloudConfig::parse(&server.uri()).unwrap();
        let tokens = Arc::new(FileTokenStore::new(dir.path().join("tokens")).unwrap());
        let client = CanvasCloudClient::new(config, store, tokens).unwrap();
        (server, client, id, dir)
    }

    #[tokio::test]
    async fn share_canvas_posts_and_stores_token() {
        let (server, client, id, _dir) = setup().await;
        Mock::given(method("POST"))
            .and(path("/api/v1/canvases"))
            .respond_with(ResponseTemplate::new(201).set_body_json(serde_json::json!({
                "slug": "demo",
                "publicUrl": format!("{}/c/demo", server.uri()),
                "apiUrl": format!("{}/api/v1/canvases/demo", server.uri()),
                "editToken": "tok-secret",
                "version": 1
            })))
            .mount(&server)
            .await;

        let res = client.share_canvas(id, Some("demo")).await.unwrap();
        assert_eq!(res.slug, "demo");
        assert_eq!(res.edit_token.as_deref(), Some("tok-secret"));
        assert!(client.tokens.get("demo").unwrap().is_some());
        assert_eq!(client.list_shared().unwrap().len(), 1);
    }

    #[tokio::test]
    async fn update_sends_edit_token_header() {
        let (server, client, id, _dir) = setup().await;
        client.tokens.set("demo", "tok-secret").unwrap();
        client
            .shares
            .upsert(ShareRecord {
                canvas: "md-one".into(),
                slug: "demo".into(),
                public_url: format!("{}/c/demo", server.uri()),
                api_url: format!("{}/api/v1/canvases/demo", server.uri()),
                shared_at: Utc::now(),
                last_version: Some(1),
                last_etag: None,
            })
            .unwrap();

        Mock::given(method("PUT"))
            .and(path("/api/v1/canvases/demo"))
            .and(header(EDIT_TOKEN_HEADER, "tok-secret"))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "slug": "demo",
                "version": 2
            })))
            .mount(&server)
            .await;

        let res = client.update_shared_canvas(id, None).await.unwrap();
        assert_eq!(res.version, Some(2));
    }
}
