//! Canvas cloud client (Phase 1 anonymous publish).
//!
//! API contract: platform `REQ-CNV-*`
//! - `POST   /api/v1/canvases`
//! - `PUT    /api/v1/canvases/{slug}`  (+ `X-Canvas-Edit-Token`)
//! - `DELETE /api/v1/canvases/{slug}`  (+ `X-Canvas-Edit-Token`)
//! - `GET    /api/v1/canvases/{slug}`  (public; ETag / 304)

mod client;
mod config;
mod credentials;
mod share_index;
mod slug;

pub use client::{CanvasCloudClient, PublishResponse, SharedCanvasInfo, UpdateSharedResponse};
pub use config::CloudConfig;
pub use credentials::{default_token_store, EditTokenStore, FileTokenStore, KeyringTokenStore};
pub use share_index::{ShareIndex, ShareRecord};
pub use slug::{normalize_slug, validate_slug};
