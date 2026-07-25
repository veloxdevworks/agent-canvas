//! Agent Canvas core: canvas IDs, schema models, validation, and file storage.

mod cloud;
mod demos;
mod error;
mod id;
mod layout;
mod schema;
mod storage;

pub use cloud::{
    default_token_store, normalize_slug, validate_slug, CanvasCloudClient, CloudConfig,
    EditTokenStore, FileTokenStore, KeyringTokenStore, PublishResponse, ShareIndex, ShareRecord,
    SharedCanvasInfo, UpdateSharedResponse,
};
pub use demos::{demo_document, demo_document_kind, matching_ids, DemoKind};
pub use error::{Error, Result};
pub use id::{CanvasId, CanvasSlot};
pub use layout::{
    density_report, density_warnings, layout_guide_document, predict_clip, DensityReport,
    PredictedClip, WidgetSize,
};
pub use schema::*;
pub use storage::{canvas_data_dir, default_store, CanvasStore};
