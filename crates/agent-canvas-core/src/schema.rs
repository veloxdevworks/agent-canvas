//! Canvas JSON schema v1 models. Keep in sync with `schema/canvas.schema.json`.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::error::{Error, Result};

fn default_schema_version() -> u32 {
    1
}

/// Root canvas document (schema version 1).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CanvasDocument {
    /// Agents often omit this; default to schema v1.
    #[serde(default = "default_schema_version")]
    pub version: u32,
    /// Optional on input; always set on write via `normalize_for_write`.
    #[serde(default = "Utc::now")]
    pub updated_at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default)]
    pub sections: Vec<Section>,
}

impl CanvasDocument {
    pub const SCHEMA_VERSION: u32 = 1;
    pub const MAX_SECTIONS: usize = 12;
    pub const MAX_LIST_ITEMS: usize = 20;
    pub const MAX_METRICS: usize = 4;
    pub const MAX_CHART_POINTS: usize = 32;

    pub fn empty() -> Self {
        Self {
            version: Self::SCHEMA_VERSION,
            updated_at: Utc::now(),
            title: None,
            sections: vec![],
        }
    }

    pub fn is_empty_content(&self) -> bool {
        self.sections.is_empty() && self.title.as_ref().map(|t| t.is_empty()).unwrap_or(true)
    }

    /// Validate structural limits. Unknown future fields on sections are not an error
    /// at the serde layer; we validate known shapes here.
    pub fn validate(&self) -> Result<()> {
        if self.version != Self::SCHEMA_VERSION {
            return Err(Error::Validation(format!(
                "unsupported version {} (expected {})",
                self.version,
                Self::SCHEMA_VERSION
            )));
        }
        if self.sections.len() > Self::MAX_SECTIONS {
            return Err(Error::Validation(format!(
                "too many sections: {} (max {})",
                self.sections.len(),
                Self::MAX_SECTIONS
            )));
        }
        for (i, section) in self.sections.iter().enumerate() {
            section.validate(i)?;
        }
        Ok(())
    }

    /// Ensure version/timestamp before write; agents may omit updatedAt.
    pub fn normalize_for_write(mut self) -> Self {
        self.version = Self::SCHEMA_VERSION;
        self.updated_at = Utc::now();
        self
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum Section {
    Header {
        text: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        subtitle: Option<String>,
        /// Lower = more important. Widget keeps highest-priority sections within size budget.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        priority: Option<u32>,
    },
    Text {
        content: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        priority: Option<u32>,
    },
    Metrics {
        items: Vec<MetricItem>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        priority: Option<u32>,
    },
    Chart {
        #[serde(rename = "chartType")]
        chart_type: ChartType,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        title: Option<String>,
        data: Vec<ChartPoint>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        priority: Option<u32>,
    },
    List {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        title: Option<String>,
        items: Vec<ListItem>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        priority: Option<u32>,
    },
    Image {
        /// Prefer `data:image/...;base64,...` or a local `file://` under app data.
        #[serde(alias = "url")]
        source: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        caption: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        priority: Option<u32>,
    },
    Spacer {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        size: Option<SpacerSize>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        priority: Option<u32>,
    },
}

impl Section {
    fn validate(&self, index: usize) -> Result<()> {
        let ctx = format!("sections[{index}]");
        match self {
            Section::Header { text, .. } => {
                if text.trim().is_empty() {
                    return Err(Error::Validation(format!("{ctx}.header: text is required")));
                }
            }
            Section::Text { content, .. } => {
                if content.trim().is_empty() {
                    return Err(Error::Validation(format!("{ctx}.text: content is required")));
                }
            }
            Section::Metrics { items, .. } => {
                if items.is_empty() || items.len() > CanvasDocument::MAX_METRICS {
                    return Err(Error::Validation(format!(
                        "{ctx}.metrics: need 1–{} items, got {}",
                        CanvasDocument::MAX_METRICS,
                        items.len()
                    )));
                }
            }
            Section::Chart { data, .. } => {
                if data.is_empty() || data.len() > CanvasDocument::MAX_CHART_POINTS {
                    return Err(Error::Validation(format!(
                        "{ctx}.chart: need 1–{} points, got {}",
                        CanvasDocument::MAX_CHART_POINTS,
                        data.len()
                    )));
                }
            }
            Section::List { items, .. } => {
                if items.len() > CanvasDocument::MAX_LIST_ITEMS {
                    return Err(Error::Validation(format!(
                        "{ctx}.list: too many items (max {})",
                        CanvasDocument::MAX_LIST_ITEMS
                    )));
                }
            }
            Section::Image { source, .. } => {
                if source.trim().is_empty() {
                    return Err(Error::Validation(format!("{ctx}.image: source is required")));
                }
                // Remote https deferred; warn via validation for v1 local-only.
                if source.starts_with("http://") || source.starts_with("https://") {
                    return Err(Error::Validation(format!(
                        "{ctx}.image: remote URLs are not supported in v1 (use data: or file://)"
                    )));
                }
            }
            Section::Spacer { .. } => {}
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MetricItem {
    pub label: String,
    pub value: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trend: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ChartType {
    #[serde(alias = "Bar", alias = "BAR")]
    Bar,
    #[serde(alias = "Line", alias = "LINE")]
    Line,
    #[serde(alias = "Pie", alias = "PIE")]
    Pie,
    #[serde(alias = "Gauge", alias = "GAUGE")]
    Gauge,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChartPoint {
    pub label: String,
    pub value: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ListItem {
    pub primary: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub secondary: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub badge: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SpacerSize {
    Sm,
    Md,
    Lg,
}

/// Summary row for `list_canvases`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CanvasSummary {
    /// Size-first id: `sm-one`, `md-two`, …
    pub id: String,
    pub size: String,
    pub slot: String,
    pub has_content: bool,
    pub updated_at: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    /// Density guide for this canvas's fixed size.
    pub layout_hint: String,
    /// Last widget render reported overflow (Phase B).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub truncated: Option<bool>,
}

/// Written by the widget after each timeline build (Phase B).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LastRender {
    pub canvas: String,
    pub size: String,
    pub truncated: bool,
    pub shown_section_count: usize,
    pub dropped_section_count: usize,
    #[serde(default)]
    pub dropped_types: Vec<String>,
    pub list_items_shown: usize,
    pub list_items_total: usize,
    pub updated_at: DateTime<Utc>,
}

impl CanvasDocument {
    pub fn peak_list_items(&self) -> usize {
        self.sections
            .iter()
            .map(|s| match s {
                Section::List { items, .. } => items.len(),
                _ => 0,
            })
            .max()
            .unwrap_or(0)
    }

    pub fn peak_chart_points(&self) -> usize {
        self.sections
            .iter()
            .map(|s| match s {
                Section::Chart { data, .. } => data.len(),
                _ => 0,
            })
            .max()
            .unwrap_or(0)
    }

    pub fn peak_text_chars(&self) -> usize {
        self.sections
            .iter()
            .map(|s| match s {
                Section::Text { content, .. } => content.chars().count(),
                Section::Header { text, subtitle, .. } => {
                    text.chars().count() + subtitle.as_ref().map(|s| s.chars().count()).unwrap_or(0)
                }
                _ => 0,
            })
            .max()
            .unwrap_or(0)
    }

    pub fn peak_metrics(&self) -> usize {
        self.sections
            .iter()
            .map(|s| match s {
                Section::Metrics { items, .. } => items.len(),
                _ => 0,
            })
            .max()
            .unwrap_or(0)
    }

    pub fn has_chart(&self) -> bool {
        self.sections
            .iter()
            .any(|s| matches!(s, Section::Chart { .. }))
    }
}
// temp - don't do this
