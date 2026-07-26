//! Size budgets + density reports for agents.
//! Packing predictions use the reference packer (`packer`) aligned with macOS ContentClip.

use serde::Serialize;
use serde_json::{json, Value};

use crate::packer;
use crate::schema::{CanvasDocument, Section};
use crate::section_meta::type_defaults_json;

/// Discrete widget sizes (WidgetKit has no freeform resize).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum WidgetSize {
    Small,
    Medium,
    Large,
    ExtraLarge,
}

impl WidgetSize {
    pub const ALL: [WidgetSize; 4] = [
        WidgetSize::Small,
        WidgetSize::Medium,
        WidgetSize::Large,
        WidgetSize::ExtraLarge,
    ];

    pub fn parse(s: &str) -> Option<Self> {
        Self::parse_short(s).or_else(|| match s.trim().to_ascii_lowercase().as_str() {
            "small" | "systemsmall" => Some(Self::Small),
            "medium" | "systemmedium" => Some(Self::Medium),
            "large" | "systemlarge" => Some(Self::Large),
            "extralarge" | "extra_large" | "extra-large" | "systemextralarge" => {
                Some(Self::ExtraLarge)
            }
            _ => None,
        })
    }

    pub fn parse_short(s: &str) -> Option<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "sm" | "s" | "small" => Some(Self::Small),
            "md" | "m" | "med" | "medium" => Some(Self::Medium),
            "lg" | "l" | "large" => Some(Self::Large),
            "xl" | "extralarge" | "extra" => Some(Self::ExtraLarge),
            _ => None,
        }
    }

    pub fn short(self) -> &'static str {
        match self {
            Self::Small => "sm",
            Self::Medium => "md",
            Self::Large => "lg",
            Self::ExtraLarge => "xl",
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Small => "small",
            Self::Medium => "medium",
            Self::Large => "large",
            Self::ExtraLarge => "extraLarge",
        }
    }

    pub fn display_label(self) -> &'static str {
        match self {
            Self::Small => "Small",
            Self::Medium => "Medium",
            Self::Large => "Large",
            Self::ExtraLarge => "Extra Large",
        }
    }

    /// Hard glance budgets — widget will clip beyond these even if write succeeds.
    pub fn budget(self) -> SizeBudget {
        match self {
            Self::Small => SizeBudget {
                size: self.short(),
                max_sections: 2,
                max_metrics: 2,
                max_list_items: 2,
                max_chart_points: 5,
                max_text_chars: 80,
                allow_chart: false,
                recipe: "metrics only, or one short header+text. No multi-chart boards.",
                summary: "Glance only: 1–2 sections. Prefer metrics. Avoid charts/lists of 3+.",
            },
            Self::Medium => SizeBudget {
                size: self.short(),
                max_sections: 4,
                max_metrics: 3,
                max_list_items: 4,
                max_chart_points: 8,
                max_text_chars: 200,
                allow_chart: true,
                recipe: "header + compact metrics (2–3) + one chart works; chart shrinks to fit. Prefer structured metrics over stuffing facts into chart titles.",
                summary: "Compact: ≤4 sections. header+metrics+chart OK; avoid long text + chart + list.",
            },
            Self::Large => SizeBudget {
                size: self.short(),
                max_sections: 6,
                max_metrics: 4,
                max_list_items: 8,
                max_chart_points: 12,
                max_text_chars: 400,
                allow_chart: true,
                recipe: "header + metrics + (chart|list) + optional short text.",
                summary: "Board: ≤6 sections. One primary chart + short list is ideal.",
            },
            Self::ExtraLarge => SizeBudget {
                size: self.short(),
                max_sections: 8,
                max_metrics: 4,
                max_list_items: 12,
                max_chart_points: 20,
                max_text_chars: 600,
                allow_chart: true,
                recipe: "richest layout; still prioritize — drop fluff before metrics/chart.",
                summary: "Roomy: ≤8 sections. Still a headline, not a document.",
            },
        }
    }

    /// Back-compat alias used by demos / older call sites.
    pub fn guide(self) -> SizeGuide {
        let b = self.budget();
        SizeGuide {
            size: self.as_str(),
            max_sections: b.max_sections,
            max_metrics: b.max_metrics,
            max_list_items: b.max_list_items,
            max_chart_points: b.max_chart_points,
            max_text_chars: b.max_text_chars,
            allow_chart: b.allow_chart,
            chart: if b.allow_chart {
                "charts OK within maxChartPoints"
            } else {
                "avoid charts; prefer metrics"
            },
            text_lines: "respect maxTextChars",
            recipe: b.recipe,
            summary: b.summary,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SizeBudget {
    pub size: &'static str,
    pub max_sections: usize,
    pub max_metrics: usize,
    pub max_list_items: usize,
    pub max_chart_points: usize,
    pub max_text_chars: usize,
    pub allow_chart: bool,
    pub recipe: &'static str,
    pub summary: &'static str,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SizeGuide {
    pub size: &'static str,
    pub max_sections: usize,
    pub max_metrics: usize,
    pub max_list_items: usize,
    pub max_chart_points: usize,
    pub max_text_chars: usize,
    pub allow_chart: bool,
    pub chart: &'static str,
    pub text_lines: &'static str,
    pub recipe: &'static str,
    pub summary: &'static str,
}

/// Structured density report returned from `update_canvas` / usable by agents to repair.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DensityReport {
    pub size: String,
    pub over_budget: bool,
    pub section_count: usize,
    pub max_sections: usize,
    pub peak_list_items: usize,
    pub max_list_items: usize,
    pub peak_chart_points: usize,
    pub max_chart_points: usize,
    pub peak_text_chars: usize,
    pub max_text_chars: usize,
    pub has_chart: bool,
    pub allow_chart: bool,
    pub peak_metrics: usize,
    pub max_metrics: usize,
    pub warnings: Vec<String>,
    /// Actionable hint when over_budget (for agent retry).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub repair_hint: Option<String>,
}

pub fn layout_guide_document() -> Value {
    json!({
        "version": 3,
        "note": "Hard glance budgets. Canvas ids are size-first (sm-one…). Widget will clip beyond budgets; use strict=true on update_canvas to reject over-budget content so you can repair. Layout constants live in Rust layout_spec (portable).",
        "idFormat": "sm|md|lg|xl - one|two|three",
        "budgets": WidgetSize::ALL.map(|s| s.budget()),
        "sectionPriority": {
            "note": "Optional sections[].priority (lower = more important, default by type). Drop priority ≠ pack rank: pack allocates height to list before chart so charts shrink into remainder.",
            "typeDefaults": type_defaults_json(),
            "packRanks": crate::section_meta::pack_ranks_json()
        },
        "styleTokens": {
            "tone": ["critical", "warning", "success", "info", "muted"],
            "emphasis": ["strong", "normal", "subtle"],
            "note": "Semantic only — platforms map to system colors/weights. Aligns with Adaptive Cards color/weight."
        },
        "actions": {
            "onOpen": "Document-level tap: expand (default) | url | file | noop.",
            "listItemAction": "Optional items[].action with the same vocabulary.",
            "urlSchemes": ["http", "https", "mailto"],
            "fileBehavior": "Reveal in Finder only; never launches.",
            "smNote": "systemSmall supports whole-tile onOpen only; per-row taps work on md/lg/xl and in the detail window."
        },
        "group": {
            "note": "type=group is detail.sections only (not glance). direction row|column; depth≤2; children≤6; atomic for clipping.",
            "direction": ["row", "column"],
            "align": ["start", "center", "end", "stretch"]
        },
        "leaves": {
            "progress": "label?, value (0…1 or absolute with max), tone?",
            "divider": "horizontal rule",
            "keyValue": "items[{key,value,tone?}]",
            "badges": "items[{text,tone?}]"
        },
        "agentTips": [
            "Call get_layout_guide or trust size in the canvas id before writing.",
            "Call get_canvas after writes to read lastRender (truncated? dropped sections).",
            "If densityReport.overBudget, shrink content and retry (or use strict=true to fail fast).",
            "Prefer fewer high-signal sections; never dump long documents into a tile.",
            "sm: no charts (metrics/header only). md: at most one chart. lg/xl: at most two charts.",
            "Always put a header first — the widget keeps the first header when clipping.",
            "Optional onOpen / list items[].action: expand|url|file|noop. url schemes: http|https|mailto only.",
            "sm tiles cannot tap individual list rows — put row actions for md+ or the expand detail window.",
            "Use tone/emphasis tokens (not hex/fonts). Put group layouts in detail.sections only."
        ],
        "portabilityGate": [
            "Expressible in Adaptive Cards and QML (at least degraded)?",
            "Styling via semantic tokens, never raw colors or point sizes?",
            "No absolute positioning or platform-only capability?",
            "Height derivable from layout_spec without platform font metrics?",
            "Policy lands in Rust; platform Shared/ gains rendering only?"
        ]
    })
}

pub fn density_report(doc: &CanvasDocument, size: WidgetSize) -> DensityReport {
    let b = size.budget();
    let section_count = doc.sections.len();
    let peak_list = doc.peak_list_items();
    let peak_chart = doc.peak_chart_points();
    let peak_text = doc.peak_text_chars();
    let peak_metrics = doc.peak_metrics();
    let has_chart = doc.has_chart();

    let mut warnings = Vec::new();
    if section_count > b.max_sections {
        warnings.push(format!(
            "sections {} > max {} for {}",
            section_count, b.max_sections, b.size
        ));
    }
    if peak_list > b.max_list_items {
        warnings.push(format!(
            "list items {} > max {} for {}",
            peak_list, b.max_list_items, b.size
        ));
    }
    if peak_chart > b.max_chart_points {
        warnings.push(format!(
            "chart points {} > max {} for {}",
            peak_chart, b.max_chart_points, b.size
        ));
    }
    if peak_text > b.max_text_chars {
        warnings.push(format!(
            "text chars {} > max {} for {}",
            peak_text, b.max_text_chars, b.size
        ));
    }
    if peak_metrics > b.max_metrics {
        warnings.push(format!(
            "metrics {} > max {} for {}",
            peak_metrics, b.max_metrics, b.size
        ));
    }
    if has_chart && !b.allow_chart {
        warnings.push(format!("charts discouraged on {} — prefer metrics", b.size));
    }
    let chart_sections = doc
        .sections
        .iter()
        .filter(|s| matches!(s, Section::Chart { .. }))
        .count();
    let chart_cap = max_charts(size);
    if chart_sections > chart_cap {
        warnings.push(format!(
            "chart sections {} > max {} for {} (extra charts will be dropped)",
            chart_sections, chart_cap, b.size
        ));
    }
    if section_count == 0 && doc.title.is_none() {
        warnings.push("empty content — widget shows empty state".into());
    }

    let over = section_count > b.max_sections
        || peak_list > b.max_list_items
        || peak_chart > b.max_chart_points
        || peak_text > b.max_text_chars
        || peak_metrics > b.max_metrics
        || (has_chart && !b.allow_chart);

    let repair_hint = if over {
        Some(format!(
            "Reduce content for size={}: max {} sections, {} list items, {} chart points, {} text chars; charts allowed={}. Recipe: {}. Drop lowest-priority sections or summarize.",
            b.size,
            b.max_sections,
            b.max_list_items,
            b.max_chart_points,
            b.max_text_chars,
            b.allow_chart,
            b.recipe
        ))
    } else {
        None
    };

    DensityReport {
        size: b.size.to_string(),
        over_budget: over,
        section_count,
        max_sections: b.max_sections,
        peak_list_items: peak_list,
        max_list_items: b.max_list_items,
        peak_chart_points: peak_chart,
        max_chart_points: b.max_chart_points,
        peak_text_chars: peak_text,
        max_text_chars: b.max_text_chars,
        has_chart,
        allow_chart: b.allow_chart,
        peak_metrics,
        max_metrics: b.max_metrics,
        warnings,
        repair_hint,
    }
}

/// Soft warnings (legacy helper).
pub fn density_warnings(
    size: WidgetSize,
    section_count: usize,
    list_item_peak: usize,
    has_chart: bool,
) -> Vec<String> {
    let b = size.budget();
    let mut w = Vec::new();
    if section_count > b.max_sections {
        w.push(format!(
            "sections={} exceeds max {} for {}",
            section_count, b.max_sections, b.size
        ));
    }
    if list_item_peak > b.max_list_items {
        w.push(format!(
            "list items peak {} exceeds max {} for {}",
            list_item_peak, b.max_list_items, b.size
        ));
    }
    if has_chart && !b.allow_chart {
        w.push(format!(
            "chart on {} often looks cramped; prefer metrics",
            b.size
        ));
    }
    if section_count == 0 {
        w.push("empty sections — widget will show empty state".into());
    }
    w
}

/// Max chart sections retained (aligned with layout_spec / Swift ContentClip).
pub fn max_charts(size: WidgetSize) -> usize {
    size.layout_spec().max_charts
}

/// Predicted clip via reference packer (matches widget ContentClip).
pub fn predict_clip(doc: &CanvasDocument, size: WidgetSize) -> PredictedClip {
    packer::predict_clip(doc, size)
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PredictedClip {
    pub will_truncate_sections: bool,
    pub shown_section_count: usize,
    pub dropped_section_count: usize,
    pub dropped_types: Vec<String>,
    pub list_items_shown: usize,
    pub list_items_total: usize,
}

/// Lower score = keep first. Explicit section.priority wins; else type default (drop priority).
#[allow(dead_code)] // used by density tooling / tests
pub fn section_sort_key(section: &Section, index: usize) -> (u32, usize) {
    let p = section
        .priority()
        .unwrap_or_else(|| section.default_priority());
    (p, index)
}

#[allow(dead_code)] // used by density tooling / tests
pub fn rank_section_indices(doc: &CanvasDocument) -> Vec<usize> {
    let mut idx: Vec<usize> = (0..doc.sections.len()).collect();
    idx.sort_by(|&a, &b| {
        section_sort_key(&doc.sections[a], a).cmp(&section_sort_key(&doc.sections[b], b))
    });
    idx
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::schema::{MetricItem, Section};

    #[test]
    fn small_full_board_is_over_budget() {
        let mut doc = CanvasDocument::empty();
        for _ in 0..5 {
            doc.sections.push(Section::Metrics {
                items: vec![MetricItem {
                    label: "A".into(),
                    value: "1".into(),
                    trend: None,
                    tone: None,
                    emphasis: None,
                }],
                priority: None,
            });
        }
        let r = density_report(&doc, WidgetSize::Small);
        assert!(r.over_budget);
        assert!(r.repair_hint.is_some());
        let clip = predict_clip(&doc, WidgetSize::Small);
        // Height packer (not max_sections) decides what fits; sm still drops overflow.
        assert!(clip.shown_section_count < 5);
        assert!(clip.dropped_section_count >= 1);
        assert!(clip.will_truncate_sections);
    }

    #[test]
    fn priority_keeps_metrics_over_text() {
        let mut doc = CanvasDocument::empty();
        doc.sections.push(Section::Text {
            content: "long".into(),
            tone: None,
            emphasis: None,
            priority: Some(50),
        });
        doc.sections.push(Section::Metrics {
            items: vec![MetricItem {
                label: "A".into(),
                value: "1".into(),
                trend: None,
                tone: None,
                emphasis: None,
            }],
            priority: Some(5),
        });
        let ranked = rank_section_indices(&doc);
        assert_eq!(ranked[0], 1); // metrics first
    }

    #[test]
    fn medium_keeps_one_chart_and_first_header() {
        use crate::schema::{ChartPoint, ChartType, ListItem};
        let mut doc = CanvasDocument::empty();
        doc.sections = vec![
            Section::Header {
                text: "Title".into(),
                subtitle: Some("sub".into()),
                tone: None,
                emphasis: None,
                priority: None,
            },
            Section::Metrics {
                items: vec![MetricItem {
                    label: "A".into(),
                    value: "1".into(),
                    trend: None,
                    tone: None,
                    emphasis: None,
                }],
                priority: None,
            },
            Section::Chart {
                chart_type: ChartType::Bar,
                title: Some("A".into()),
                data: vec![ChartPoint {
                    label: "M".into(),
                    value: 1.0,
                }],
                priority: None,
            },
            Section::Chart {
                chart_type: ChartType::Line,
                title: Some("B".into()),
                data: vec![ChartPoint {
                    label: "M".into(),
                    value: 2.0,
                }],
                priority: None,
            },
            Section::List {
                title: Some("Q".into()),
                items: vec![ListItem {
                    primary: "x".into(),
                    secondary: None,
                    badge: None,
                    action: None,
                    tone: None,
                    emphasis: None,
                }],
                priority: None,
            },
            Section::Text {
                content: "tail".into(),
                tone: None,
                emphasis: None,
                priority: None,
            },
        ];
        let clip = predict_clip(&doc, WidgetSize::Medium);
        assert!(clip.will_truncate_sections);
        let charts_dropped = clip.dropped_types.iter().filter(|t| *t == "chart").count();
        assert!(charts_dropped >= 1, "md should drop at least one chart");
    }
}
