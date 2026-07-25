//! Agent Canvas core: canvas IDs, schema models, validation, and file storage.

mod demos;
mod error;
mod id;
mod layout;
mod schema;
mod storage;

pub use demos::{demo_document, demo_document_kind, matching_ids, DemoKind};
pub use error::{Error, Result};
pub use id::{CanvasId, CanvasSlot};
pub use layout::{
    density_report, density_warnings, layout_guide_document, predict_clip, DensityReport,
    PredictedClip, WidgetSize,
};
pub use schema::*;
pub use storage::{CanvasStore, canvas_data_dir, default_store};
