//! Agent Canvas core: canvas IDs, schema models, validation, and file storage.
#![recursion_limit = "512"]

mod cloud;
mod conformance;
mod demos;
mod error;
mod history;
mod id;
mod layout;
mod layout_spec;
mod packer;
mod schema;
mod schema_gen;
mod section_meta;
mod storage;

pub use cloud::{
    default_token_store, normalize_slug, validate_slug, CanvasCloudClient, CloudConfig,
    EditTokenStore, FileTokenStore, KeyringTokenStore, PublishResponse, ShareIndex, ShareRecord,
    SharedCanvasInfo, UpdateSharedResponse,
};
pub use demos::{demo_document, demo_document_kind, matching_ids, DemoKind};
pub use error::{Error, Result};
pub use history::{
    archive_if_needed, content_equal, delete_entry as delete_history_entry, history_dir,
    list as list_history, load as load_history, HistoryEntryMeta, HistorySource,
    MAX_HISTORY_ENTRIES,
};
pub use id::{CanvasId, CanvasSlot};
pub use layout::{
    density_report, density_warnings, layout_guide_document, predict_clip, DensityReport,
    PredictedClip, WidgetSize,
};
pub use layout_spec::{generate_swift_layout_spec, layout_spec, LayoutSpec, SizeLayoutSpec};
pub use packer::{estimated_height, pack, PackResult};
pub use schema::*;
pub use schema_gen::{generate_canvas_schema, generate_canvas_schema_string};
pub use section_meta::{SectionKind, SectionMeta, SECTION_META};
pub use storage::{canvas_data_dir, default_store, CanvasStore};
