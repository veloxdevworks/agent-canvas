//! Canvas JSON schema v1 models. Keep in sync with `schema/canvas.schema.json`
//! (generated via `schema_gen`; verified by tests).

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::assets;
use crate::error::{Error, Result};
use crate::section_meta::SectionKind;

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
    /// Full-bleed glance image. When set, replaces tile chrome/sections on the widget.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cover: Option<Cover>,
    /// What happens when the user taps the widget tile (default: expand).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub on_open: Option<Action>,
    #[serde(default)]
    pub sections: Vec<Section>,
    /// Optional richer layout for the expand detail window.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub detail: Option<CanvasDetail>,
}

/// Full-bleed cover image for the glance tile.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Cover {
    /// `asset:{sha256}.{png|jpg}` after write; `data:image/...;base64,...` accepted on input.
    pub source: String,
    /// Accessibility label and decode-failure fallback string.
    pub alt: String,
    /// How the image fills the tile (default: cover).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fit: Option<CoverFit>,
}

/// Semantic fit token — never point sizes.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub enum CoverFit {
    /// Fill and crop (default).
    #[default]
    Cover,
    /// Letterbox to fit.
    Contain,
}

impl Cover {
    pub fn validate(&self, ctx: &str) -> Result<()> {
        if self.alt.trim().is_empty() {
            return Err(Error::Validation(format!("{ctx}: alt is required")));
        }
        assets::validate_image_source(&self.source, ctx)?;
        Ok(())
    }

    pub fn fit_or_default(&self) -> CoverFit {
        self.fit.unwrap_or_default()
    }
}

/// Height token for inline `image` sections.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub enum ImageHeight {
    Small,
    #[default]
    Medium,
    Large,
}

/// Tailored expanded-view content (not counted toward glance density).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CanvasDetail {
    #[serde(default)]
    pub sections: Vec<Section>,
}

impl CanvasDocument {
    pub const SCHEMA_VERSION: u32 = 1;
    pub const MAX_SECTIONS: usize = 12;
    pub const MAX_DETAIL_SECTIONS: usize = 24;
    pub const MAX_LIST_ITEMS: usize = 20;
    pub const MAX_METRICS: usize = 4;
    pub const MAX_CHART_POINTS: usize = 32;
    pub const MAX_GROUP_CHILDREN: usize = 6;
    pub const MAX_GROUP_DEPTH: usize = 2;
    pub const MAX_KEY_VALUE: usize = 12;
    pub const MAX_BADGES: usize = 12;

    pub fn empty() -> Self {
        Self {
            version: Self::SCHEMA_VERSION,
            updated_at: Utc::now(),
            title: None,
            cover: None,
            on_open: None,
            sections: vec![],
            detail: None,
        }
    }

    pub fn is_empty_content(&self) -> bool {
        if self.cover.is_some() {
            return false;
        }
        self.sections.is_empty() && self.title.as_ref().map(|t| t.is_empty()).unwrap_or(true)
    }

    /// Effective sections for the expand detail window.
    pub fn detail_sections(&self) -> &[Section] {
        if let Some(detail) = &self.detail {
            if !detail.sections.is_empty() {
                return &detail.sections;
            }
        }
        &self.sections
    }

    /// Validate structural limits.
    ///
    /// **Unknown section types:** Rust rejects them on deserialize (strict write
    /// path). Swift tolerates unknown `type` values as `.unknown` for forward-
    /// compatible widget reads. That asymmetry is intentional — see plan.md.
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
        if let Some(cover) = &self.cover {
            cover.validate("cover")?;
        }
        if let Some(on_open) = &self.on_open {
            on_open.validate("onOpen")?;
        }
        for (i, section) in self.sections.iter().enumerate() {
            section.validate(&format!("sections[{i}]"), 0, true)?;
        }
        if let Some(detail) = &self.detail {
            if detail.sections.len() > Self::MAX_DETAIL_SECTIONS {
                return Err(Error::Validation(format!(
                    "detail.sections: too many sections: {} (max {})",
                    detail.sections.len(),
                    Self::MAX_DETAIL_SECTIONS
                )));
            }
            for (i, section) in detail.sections.iter().enumerate() {
                section.validate(&format!("detail.sections[{i}]"), 0, false)?;
            }
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

/// Declarative intent shared by document `onOpen` and per-item `action`.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum Action {
    /// Open the host detail window (`detail.sections` if present, else `sections`).
    Expand,
    Url {
        url: String,
    },
    File {
        path: String,
    },
    Noop,
}

impl Action {
    pub fn validate(&self, ctx: &str) -> Result<()> {
        match self {
            Action::Expand | Action::Noop => Ok(()),
            Action::Url { url } => validate_action_url(url, ctx),
            Action::File { path } => {
                if path.trim().is_empty() {
                    return Err(Error::Validation(format!(
                        "{ctx}.file: path is required"
                    )));
                }
                if path.contains('\0') {
                    return Err(Error::Validation(format!(
                        "{ctx}.file: path must not contain NUL"
                    )));
                }
                Ok(())
            }
        }
    }
}

fn validate_action_url(url: &str, ctx: &str) -> Result<()> {
    let trimmed = url.trim();
    if trimmed.is_empty() {
        return Err(Error::Validation(format!("{ctx}.url: url is required")));
    }
    let parsed = url::Url::parse(trimmed).map_err(|e| {
        Error::Validation(format!("{ctx}.url: invalid URL ({e})"))
    })?;
    let scheme = parsed.scheme().to_ascii_lowercase();
    match scheme.as_str() {
        "http" | "https" | "mailto" => {}
        other => {
            return Err(Error::Validation(format!(
                "{ctx}.url: scheme `{other}` is not allowed (use http, https, or mailto)"
            )));
        }
    }
    if !parsed.username().is_empty() || parsed.password().is_some() {
        return Err(Error::Validation(format!(
            "{ctx}.url: embedded credentials are not allowed"
        )));
    }
    Ok(())
}

/// Semantic tone (maps to Adaptive Cards `color` / system semantic colors).
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum Tone {
    Critical,
    Warning,
    Success,
    Info,
    Muted,
}

/// Semantic emphasis (maps to Adaptive Cards `weight` / system font weights).
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum Emphasis {
    Strong,
    Normal,
    Subtle,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum GroupDirection {
    Row,
    Column,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum GroupAlign {
    Start,
    Center,
    End,
    Stretch,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum Section {
    Header {
        text: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        subtitle: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        tone: Option<Tone>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        emphasis: Option<Emphasis>,
        /// Lower = more important. Widget keeps highest-priority sections within size budget.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        priority: Option<u32>,
    },
    Text {
        content: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        tone: Option<Tone>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        emphasis: Option<Emphasis>,
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
        /// Prefer `asset:{sha}.{ext}` (after write) or `data:image/...;base64,...` on input.
        #[serde(alias = "url")]
        source: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        caption: Option<String>,
        /// Height token: small | medium | large (default medium).
        #[serde(default, skip_serializing_if = "Option::is_none")]
        height: Option<ImageHeight>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        priority: Option<u32>,
    },
    Spacer {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        size: Option<SpacerSize>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        priority: Option<u32>,
    },
    /// Flex container. Detail-only for glance tiles (rejected in `sections`).
    Group {
        direction: GroupDirection,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        gap: Option<SpacerSize>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        align: Option<GroupAlign>,
        children: Vec<Section>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        weight: Option<u32>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        priority: Option<u32>,
    },
    Progress {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        label: Option<String>,
        /// Fraction 0…1, or absolute when `max` is set.
        value: f64,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        max: Option<f64>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        tone: Option<Tone>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        priority: Option<u32>,
    },
    Divider {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        priority: Option<u32>,
    },
    KeyValue {
        items: Vec<KeyValueItem>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        priority: Option<u32>,
    },
    Badges {
        items: Vec<BadgeItem>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        priority: Option<u32>,
    },
}

impl Section {
    pub fn kind(&self) -> SectionKind {
        match self {
            Section::Header { .. } => SectionKind::Header,
            Section::Text { .. } => SectionKind::Text,
            Section::Metrics { .. } => SectionKind::Metrics,
            Section::Chart { .. } => SectionKind::Chart,
            Section::List { .. } => SectionKind::List,
            Section::Image { .. } => SectionKind::Image,
            Section::Spacer { .. } => SectionKind::Spacer,
            Section::Group { .. } => SectionKind::Group,
            Section::Progress { .. } => SectionKind::Progress,
            Section::Divider { .. } => SectionKind::Divider,
            Section::KeyValue { .. } => SectionKind::KeyValue,
            Section::Badges { .. } => SectionKind::Badges,
        }
    }

    fn validate(&self, ctx: &str, depth: usize, glance: bool) -> Result<()> {
        let kind = self.kind();
        if glance && !kind.glance_allowed() {
            return Err(Error::Validation(format!(
                "{ctx}.{}: not allowed in glance sections (use detail.sections)",
                kind.type_name()
            )));
        }
        match self {
            Section::Header { text, .. } => {
                if text.trim().is_empty() {
                    return Err(Error::Validation(format!("{ctx}.header: text is required")));
                }
            }
            Section::Text { content, .. } => {
                if content.trim().is_empty() {
                    return Err(Error::Validation(format!(
                        "{ctx}.text: content is required"
                    )));
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
                for (j, item) in items.iter().enumerate() {
                    if let Some(action) = &item.action {
                        action.validate(&format!("{ctx}.items[{j}].action"))?;
                    }
                }
            }
            Section::Image { source, .. } => {
                assets::validate_image_source(source, &format!("{ctx}.image"))?;
            }
            Section::Spacer { .. } => {}
            Section::Group { children, .. } => {
                if depth >= CanvasDocument::MAX_GROUP_DEPTH {
                    return Err(Error::Validation(format!(
                        "{ctx}.group: max nesting depth is {}",
                        CanvasDocument::MAX_GROUP_DEPTH
                    )));
                }
                if children.is_empty() || children.len() > CanvasDocument::MAX_GROUP_CHILDREN {
                    return Err(Error::Validation(format!(
                        "{ctx}.group: need 1–{} children, got {}",
                        CanvasDocument::MAX_GROUP_CHILDREN,
                        children.len()
                    )));
                }
                for (j, child) in children.iter().enumerate() {
                    // Nested groups inherit glance restriction of the outer surface.
                    child.validate(&format!("{ctx}.children[{j}]"), depth + 1, glance)?;
                }
            }
            Section::Progress { value, max, .. } => {
                if !value.is_finite() {
                    return Err(Error::Validation(format!(
                        "{ctx}.progress: value must be finite"
                    )));
                }
                if let Some(m) = max {
                    if !m.is_finite() || *m <= 0.0 {
                        return Err(Error::Validation(format!(
                            "{ctx}.progress: max must be a positive finite number"
                        )));
                    }
                }
            }
            Section::Divider { .. } => {}
            Section::KeyValue { items, .. } => {
                if items.is_empty() || items.len() > CanvasDocument::MAX_KEY_VALUE {
                    return Err(Error::Validation(format!(
                        "{ctx}.keyValue: need 1–{} items, got {}",
                        CanvasDocument::MAX_KEY_VALUE,
                        items.len()
                    )));
                }
            }
            Section::Badges { items, .. } => {
                if items.is_empty() || items.len() > CanvasDocument::MAX_BADGES {
                    return Err(Error::Validation(format!(
                        "{ctx}.badges: need 1–{} items, got {}",
                        CanvasDocument::MAX_BADGES,
                        items.len()
                    )));
                }
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MetricItem {
    pub label: String,
    pub value: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trend: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tone: Option<Tone>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub emphasis: Option<Emphasis>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
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

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ChartPoint {
    pub label: String,
    pub value: f64,
}

impl Eq for ChartPoint {}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ListItem {
    pub primary: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub secondary: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub badge: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub action: Option<Action>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tone: Option<Tone>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub emphasis: Option<Emphasis>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct KeyValueItem {
    pub key: String,
    pub value: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tone: Option<Tone>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BadgeItem {
    pub text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tone: Option<Tone>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum SpacerSize {
    Sm,
    Md,
    Lg,
}

impl SpacerSize {
    pub fn gap_points(self) -> f64 {
        match self {
            SpacerSize::Sm => 4.0,
            SpacerSize::Md => 8.0,
            SpacerSize::Lg => 12.0,
        }
    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn action_url_allows_https() {
        let a = Action::Url {
            url: "https://example.com/x".into(),
        };
        a.validate("onOpen").unwrap();
    }

    #[test]
    fn action_url_rejects_file_scheme() {
        let a = Action::Url {
            url: "file:///tmp/x".into(),
        };
        let err = a.validate("onOpen").unwrap_err().to_string();
        assert!(err.contains("not allowed"), "{err}");
    }

    #[test]
    fn action_url_rejects_javascript() {
        let a = Action::Url {
            url: "javascript:alert(1)".into(),
        };
        assert!(a.validate("onOpen").is_err());
    }

    #[test]
    fn action_url_rejects_agentcanvas() {
        let a = Action::Url {
            url: "agentcanvas://detail?id=md-one".into(),
        };
        assert!(a.validate("onOpen").is_err());
    }

    #[test]
    fn action_url_rejects_credentials() {
        let a = Action::Url {
            url: "https://user:pass@example.com/".into(),
        };
        let err = a.validate("onOpen").unwrap_err().to_string();
        assert!(err.contains("credentials"), "{err}");
    }

    #[test]
    fn action_url_allows_mailto() {
        let a = Action::Url {
            url: "mailto:feedback@example.com".into(),
        };
        a.validate("onOpen").unwrap();
    }

    #[test]
    fn document_with_on_open_and_list_action_roundtrips() {
        let raw = json!({
            "version": 1,
            "title": "Actions",
            "onOpen": { "type": "expand" },
            "sections": [{
                "type": "list",
                "items": [{
                    "primary": "Open docs",
                    "action": { "type": "url", "url": "https://example.com" }
                }]
            }],
            "detail": {
                "sections": [{
                    "type": "header",
                    "text": "Expanded"
                }]
            }
        });
        let doc: CanvasDocument = serde_json::from_value(raw).unwrap();
        doc.validate().unwrap();
        assert!(matches!(doc.on_open, Some(Action::Expand)));
        let Section::List { items, .. } = &doc.sections[0] else {
            panic!("expected list");
        };
        assert!(matches!(
            &items[0].action,
            Some(Action::Url { url }) if url == "https://example.com"
        ));
        assert_eq!(doc.detail_sections()[0].type_name(), "header");
    }

    #[test]
    fn invalid_list_action_fails_validate() {
        let mut doc = CanvasDocument::empty();
        doc.sections.push(Section::List {
            title: None,
            items: vec![ListItem {
                primary: "Bad".into(),
                secondary: None,
                badge: None,
                action: Some(Action::Url {
                    url: "data:text/plain,hi".into(),
                }),
                tone: None,
                emphasis: None,
            }],
            priority: None,
        });
        let err = doc.validate().unwrap_err().to_string();
        assert!(err.contains("sections[0].items[0].action"), "{err}");
    }

    #[test]
    fn group_rejected_in_glance() {
        let mut doc = CanvasDocument::empty();
        doc.sections.push(Section::Group {
            direction: GroupDirection::Row,
            gap: None,
            align: None,
            children: vec![Section::Text {
                content: "hi".into(),
                tone: None,
                emphasis: None,
                priority: None,
            }],
            weight: None,
            priority: None,
        });
        let err = doc.validate().unwrap_err().to_string();
        assert!(err.contains("detail.sections"), "{err}");
    }

    #[test]
    fn group_allowed_in_detail() {
        let mut doc = CanvasDocument::empty();
        doc.detail = Some(CanvasDetail {
            sections: vec![Section::Group {
                direction: GroupDirection::Column,
                gap: Some(SpacerSize::Sm),
                align: None,
                children: vec![
                    Section::Header {
                        text: "A".into(),
                        subtitle: None,
                        tone: Some(Tone::Success),
                        emphasis: Some(Emphasis::Strong),
                        priority: None,
                    },
                    Section::Progress {
                        label: Some("Done".into()),
                        value: 0.75,
                        max: None,
                        tone: None,
                        priority: None,
                    },
                ],
                weight: None,
                priority: None,
            }],
        });
        doc.validate().unwrap();
    }

    #[test]
    fn tone_emphasis_roundtrip() {
        let raw = json!({
            "version": 1,
            "sections": [{
                "type": "metrics",
                "items": [{
                    "label": "Err",
                    "value": "3",
                    "tone": "critical",
                    "emphasis": "strong"
                }]
            }]
        });
        let doc: CanvasDocument = serde_json::from_value(raw).unwrap();
        doc.validate().unwrap();
        let Section::Metrics { items, .. } = &doc.sections[0] else {
            panic!("metrics");
        };
        assert_eq!(items[0].tone, Some(Tone::Critical));
        assert_eq!(items[0].emphasis, Some(Emphasis::Strong));
    }

    #[test]
    fn new_leaves_roundtrip() {
        let raw = json!({
            "version": 1,
            "sections": [
                { "type": "divider" },
                { "type": "progress", "label": "Build", "value": 0.4, "tone": "info" },
                { "type": "keyValue", "items": [{ "key": "Env", "value": "prod" }] },
                { "type": "badges", "items": [{ "text": "beta", "tone": "warning" }] }
            ]
        });
        let doc: CanvasDocument = serde_json::from_value(raw).unwrap();
        doc.validate().unwrap();
        assert_eq!(doc.sections.len(), 4);
    }
}
