//! Reference packer — bit-compatible with macOS `ContentClip.apply`.
//! Heights come from `layout_spec` (no text measurement).

use serde::Serialize;

use crate::layout::WidgetSize;
use crate::layout_spec::SizeLayoutSpec;
use crate::schema::{CanvasDocument, Section};

/// Result of packing a document into a widget size budget.
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PackResult {
    pub shown_indices: Vec<usize>,
    pub dropped_types: Vec<String>,
    pub truncated: bool,
    pub list_items_shown: usize,
    pub list_items_total: usize,
    pub chart_height_scale: f64,
    pub shown_section_count: usize,
    pub dropped_section_count: usize,
    /// True when document has a cover — glance renders full-bleed, sections unused.
    pub cover: bool,
}

impl PackResult {
    pub fn will_truncate_sections(&self) -> bool {
        self.dropped_section_count > 0
    }
}

/// Pack `document` for `size` (optional override max content height).
pub fn pack(
    document: &CanvasDocument,
    size: WidgetSize,
    max_height: Option<f64>,
) -> PackResult {
    if document.cover.is_some() {
        return PackResult {
            shown_indices: vec![],
            dropped_types: vec![],
            truncated: false,
            list_items_shown: 0,
            list_items_total: 0,
            chart_height_scale: 1.0,
            shown_section_count: 0,
            dropped_section_count: 0,
            cover: true,
        };
    }

    let spec = size.layout_spec();
    let budget = max_height.unwrap_or_else(|| default_content_height(&spec));
    let spacing = spec.section_spacing;

    let candidates = prioritized_candidates(document, &spec);

    let mut packed: Vec<Option<PackedSection>> = vec![None; document.sections.len()];
    let mut chart_scales: Vec<Option<f64>> = vec![None; document.sections.len()];
    let mut used = 0.0_f64;
    let mut list_shown = 0usize;
    let mut list_total = 0usize;

    for (index, section) in candidates {
        if packed[index].is_some() {
            continue;
        }
        let gap = if packed.iter().any(|p| p.is_some()) {
            spacing
        } else {
            0.0
        };
        let remaining = budget - used - gap;
        if remaining < 8.0 {
            break;
        }

        if let Section::List {
            title,
            items,
            priority,
        } = section
        {
            list_total = list_total.max(items.len());
            let effective_title = if size == WidgetSize::Small {
                None
            } else {
                title.clone()
            };
            if let Some(fit) = fit_list(
                &effective_title,
                items,
                *priority,
                &spec,
                remaining,
            ) {
                list_shown = list_shown.max(fit.rows);
                used += gap + fit.height;
                packed[index] = Some(fit.section);
            }
            continue;
        }

        let clipped = clip_for_pack(section, size, &spec);

        if matches!(&clipped, Section::Chart { .. }) {
            if let Some(fit) = fit_chart(&clipped, &spec, remaining) {
                chart_scales[index] = Some(fit.scale);
                used += gap + fit.height;
                packed[index] = Some(fit.section);
            }
            continue;
        }

        let h = estimated_height(&clipped, &spec, None);
        if h > remaining {
            continue;
        }
        packed[index] = Some(clipped);
        used += gap + h;
    }

    // Retry skipped lists.
    if used < budget {
        for (index, section) in document.sections.iter().enumerate() {
            if packed[index].is_some() {
                continue;
            }
            let Section::List {
                title,
                items,
                priority,
            } = section
            else {
                continue;
            };
            let gap = if packed.iter().any(|p| p.is_some()) {
                spacing
            } else {
                0.0
            };
            let remaining = budget - used - gap;
            list_total = list_total.max(items.len());
            let effective_title = if size == WidgetSize::Small {
                None
            } else {
                title.clone()
            };
            if let Some(fit) = fit_list(
                &effective_title,
                items,
                *priority,
                &spec,
                remaining,
            ) {
                list_shown = list_shown.max(fit.rows);
                used += gap + fit.height;
                packed[index] = Some(fit.section);
            }
        }
    }

    // Last chance: shrink skipped charts.
    if used < budget {
        for (index, section) in document.sections.iter().enumerate() {
            if packed[index].is_some() {
                continue;
            }
            if !matches!(section, Section::Chart { .. }) {
                continue;
            }
            let gap = if packed.iter().any(|p| p.is_some()) {
                spacing
            } else {
                0.0
            };
            let remaining = budget - used - gap;
            let clipped = clip_non_list(section, size, &spec);
            if let Some(fit) = fit_chart(&clipped, &spec, remaining) {
                chart_scales[index] = Some(fit.scale);
                used += gap + fit.height;
                packed[index] = Some(fit.section);
            }
        }
    }

    // Force ≥1 list row.
    if list_shown == 0 {
        for (index, section) in document.sections.iter().enumerate() {
            let Section::List {
                title,
                items,
                priority,
            } = section
            else {
                continue;
            };
            let Some(first) = items.first() else {
                continue;
            };
            list_total = list_total.max(items.len());
            packed[index] = Some(Section::List {
                title: if size == WidgetSize::Small {
                    None
                } else {
                    title.clone()
                },
                items: vec![first.clone()],
                priority: *priority,
            });
            list_shown = 1;
            break;
        }
    }

    if packed.iter().all(|p| p.is_none()) {
        if let Some(first) = document.sections.first() {
            packed[0] = Some(clip_non_list(first, size, &spec));
        }
    }

    let mut shown_indices = Vec::new();
    let mut dropped_types = Vec::new();
    let mut min_chart_scale: Option<f64> = None;
    for (i, section) in document.sections.iter().enumerate() {
        if packed[i].is_some() {
            shown_indices.push(i);
            if let Some(s) = chart_scales[i] {
                min_chart_scale = Some(min_chart_scale.map(|m| m.min(s)).unwrap_or(s));
            }
        } else {
            dropped_types.push(section.type_name().to_string());
            if let Section::List { items, .. } = section {
                list_total = list_total.max(items.len());
            }
        }
    }

    let truncated = !dropped_types.is_empty() || list_total > list_shown;
    PackResult {
        shown_section_count: shown_indices.len(),
        dropped_section_count: dropped_types.len(),
        shown_indices,
        dropped_types,
        truncated,
        list_items_shown: list_shown,
        list_items_total: list_total,
        chart_height_scale: min_chart_scale.unwrap_or(spec.chart_height_scale),
        cover: false,
    }
}

type PackedSection = Section;

struct ChartFit {
    section: Section,
    height: f64,
    scale: f64,
}

struct ListFit {
    section: Section,
    height: f64,
    rows: usize,
}

fn default_content_height(spec: &SizeLayoutSpec) -> f64 {
    content_budget(spec, true, true, true)
}

fn content_budget(
    spec: &SizeLayoutSpec,
    has_title: bool,
    has_timestamp: bool,
    reserve_overflow: bool,
) -> f64 {
    let tile_h = spec.tile_height;
    let inset = spec.edge_inset * 2.0;
    let chrome = chrome_height(spec, has_title, reserve_overflow, has_timestamp);
    (tile_h - inset - chrome).max(48.0)
}

fn chrome_height(
    spec: &SizeLayoutSpec,
    has_title: bool,
    show_overflow: bool,
    has_timestamp: bool,
) -> f64 {
    let gap = if spec.size == "md" { 4.0 } else { 6.0 };
    let mut h = 0.0;
    if has_title {
        h += spec.title_chrome_height + gap;
    }
    let mut footer_blocks = 0;
    if show_overflow {
        h += spec.overflow_line_height;
        footer_blocks += 1;
    }
    if has_timestamp {
        h += spec.timestamp_height;
        footer_blocks += 1;
    }
    if footer_blocks > 1 {
        h += 3.0;
    }
    if footer_blocks > 0 {
        h += 3.0;
    }
    h
}

fn list_section_height(spec: &SizeLayoutSpec, title: Option<&str>, rows: usize) -> f64 {
    let title_h = if title.map(|t| !t.is_empty()).unwrap_or(false) {
        spec.list_title_height
    } else {
        0.0
    };
    let blocks = (if title_h > 0.0 { 1 } else { 0 }) + rows;
    let spacing = if blocks > 1 {
        (blocks - 1) as f64 * 3.0
    } else {
        0.0
    };
    title_h + (rows as f64) * spec.list_row_height + spacing
}

/// Compositional height estimate for a section (and nested group children).
pub fn estimated_height(
    section: &Section,
    spec: &SizeLayoutSpec,
    chart_scale: Option<f64>,
) -> f64 {
    match section {
        Section::Header { subtitle, .. } => {
            if subtitle.is_none() {
                spec.header_height_no_subtitle
            } else {
                spec.header_height_with_subtitle
            }
        }
        Section::Metrics { .. } => spec.metrics_height,
        Section::Chart { title, .. } => {
            let scale = chart_scale.unwrap_or(spec.chart_height_scale);
            let plot = (spec.chart_plot_height * scale).max(22.0);
            let title_h = if title.as_ref().map(|t| !t.is_empty()).unwrap_or(false) {
                12.0
            } else {
                0.0
            };
            let gap = if title_h > 0.0 { 2.0 } else { 0.0 };
            title_h + gap + plot
        }
        Section::List { title, items, .. } => {
            list_section_height(spec, title.as_deref(), items.len())
        }
        Section::Text { .. } => spec.text_height,
        Section::Image { height, .. } => {
            spec.image_height_for(height.unwrap_or_default())
        }
        Section::Spacer { size, .. } => size.map(|s| s.gap_points()).unwrap_or(spec.spacer_height),
        Section::Progress { .. } => spec.progress_height,
        Section::Divider { .. } => spec.divider_height,
        Section::KeyValue { items, .. } => {
            let n = items.len().max(1) as f64;
            n * spec.key_value_row_height + (n - 1.0).max(0.0) * 2.0
        }
        Section::Badges { .. } => spec.badges_height,
        Section::Group {
            direction,
            gap,
            children,
            ..
        } => {
            let child_heights: Vec<f64> = children
                .iter()
                .map(|c| estimated_height(c, spec, None))
                .collect();
            let gap_pts = gap.map(|g| g.gap_points()).unwrap_or(4.0);
            match direction {
                crate::schema::GroupDirection::Row => {
                    child_heights.into_iter().fold(0.0_f64, f64::max)
                }
                crate::schema::GroupDirection::Column => {
                    let sum: f64 = child_heights.iter().sum();
                    let gaps = if children.len() > 1 {
                        (children.len() - 1) as f64 * gap_pts
                    } else {
                        0.0
                    };
                    sum + gaps
                }
            }
        }
    }
}

fn fit_chart(section: &Section, spec: &SizeLayoutSpec, max_height: f64) -> Option<ChartFit> {
    let Section::Chart {
        chart_type,
        title,
        data,
        priority,
    } = section
    else {
        return None;
    };
    let base = spec.chart_height_scale;
    let scales = [
        base,
        base * 0.85,
        base * 0.7,
        base * 0.55,
        0.5,
        0.4,
    ];
    let variants = [
        Section::Chart {
            chart_type: *chart_type,
            title: title.clone(),
            data: data.clone(),
            priority: *priority,
        },
        Section::Chart {
            chart_type: *chart_type,
            title: None,
            data: data.clone(),
            priority: *priority,
        },
    ];
    for variant in &variants {
        for scale in scales {
            let h = estimated_height(variant, spec, Some(scale));
            if h <= max_height {
                return Some(ChartFit {
                    section: variant.clone(),
                    height: h,
                    scale,
                });
            }
        }
    }
    None
}

fn fit_list(
    title: &Option<String>,
    items: &[crate::schema::ListItem],
    priority: Option<u32>,
    spec: &SizeLayoutSpec,
    max_height: f64,
) -> Option<ListFit> {
    if items.is_empty() {
        return None;
    }
    let cap = spec.list_item_cap.min(items.len());

    let best = |section_title: Option<&str>| -> Option<ListFit> {
        let mut best_rows = 0usize;
        let mut best_h = 0.0;
        for rows in 1..=cap {
            let h = list_section_height(spec, section_title, rows);
            if h <= max_height {
                best_rows = rows;
                best_h = h;
            } else {
                break;
            }
        }
        if best_rows == 0 {
            return None;
        }
        Some(ListFit {
            section: Section::List {
                title: section_title.map(str::to_string),
                items: items[..best_rows].to_vec(),
                priority,
            },
            height: best_h,
            rows: best_rows,
        })
    };

    let without = best(None);
    let with = if title.is_some() {
        best(title.as_deref())
    } else {
        None
    };

    match (with, without) {
        (Some(w), Some(wo)) => {
            if wo.rows > w.rows {
                Some(wo)
            } else {
                Some(w)
            }
        }
        (w, wo) => w.or(wo),
    }
}

fn prioritized_candidates<'a>(
    document: &'a CanvasDocument,
    spec: &SizeLayoutSpec,
) -> Vec<(usize, &'a Section)> {
    let chart_cap = spec.max_charts;
    let mut indexed: Vec<(usize, &Section)> = document.sections.iter().enumerate().collect();
    indexed.sort_by(|a, b| {
        let ra = a.1.kind().pack_rank();
        let rb = b.1.kind().pack_rank();
        ra.cmp(&rb).then(a.0.cmp(&b.0))
    });

    let mut charts = 0usize;
    let mut result = Vec::new();
    for (i, section) in indexed {
        if matches!(section, Section::Chart { .. }) {
            if charts >= chart_cap {
                continue;
            }
            charts += 1;
        }
        result.push((i, section));
    }
    result
}

fn clip_for_pack(section: &Section, size: WidgetSize, spec: &SizeLayoutSpec) -> Section {
    // sm/md: keep header primary; subtitle optional density (matches Swift ContentClip).
    if matches!(size, WidgetSize::Small | WidgetSize::Medium) {
        if let Section::Header {
            text,
            subtitle,
            tone,
            emphasis,
            priority,
        } = section
        {
            let keep_sub = if size == WidgetSize::Small {
                None
            } else {
                match subtitle {
                    Some(s) if !s.is_empty() && s.chars().count() <= 36 => Some(s.clone()),
                    Some(_) => None,
                    None => None,
                }
            };
            return Section::Header {
                text: text.clone(),
                subtitle: keep_sub,
                tone: *tone,
                emphasis: *emphasis,
                priority: *priority,
            };
        }
    }
    clip_non_list(section, size, spec)
}

fn clip_non_list(section: &Section, size: WidgetSize, spec: &SizeLayoutSpec) -> Section {
    match section {
        Section::Chart {
            chart_type,
            title,
            data,
            priority,
        } => {
            let lim = match size {
                WidgetSize::Small => 5,
                WidgetSize::Medium => 8,
                WidgetSize::Large => 12,
                WidgetSize::ExtraLarge => 16,
            };
            Section::Chart {
                chart_type: *chart_type,
                title: title.clone(),
                data: data.iter().take(lim).cloned().collect(),
                priority: *priority,
            }
        }
        Section::Metrics { items, priority } => {
            let lim = if size == WidgetSize::Small {
                2
            } else {
                spec.max_metrics.min(4)
            };
            Section::Metrics {
                items: items.iter().take(lim).cloned().collect(),
                priority: *priority,
            }
        }
        Section::Text {
            content,
            tone,
            emphasis,
            priority,
        } => {
            let lim = spec.max_text_chars;
            if content.chars().count() <= lim {
                section.clone()
            } else {
                let truncated: String = content.chars().take(lim).collect();
                Section::Text {
                    content: format!("{truncated}…"),
                    tone: *tone,
                    emphasis: *emphasis,
                    priority: *priority,
                }
            }
        }
        Section::List {
            title,
            items,
            priority,
        } => Section::List {
            title: title.clone(),
            items: items.iter().take(spec.list_item_cap).cloned().collect(),
            priority: *priority,
        },
        other => other.clone(),
    }
}

impl Section {
    pub fn type_name(&self) -> &'static str {
        self.kind().type_name()
    }

    pub fn priority(&self) -> Option<u32> {
        match self {
            Section::Header { priority, .. }
            | Section::Text { priority, .. }
            | Section::Metrics { priority, .. }
            | Section::Chart { priority, .. }
            | Section::List { priority, .. }
            | Section::Image { priority, .. }
            | Section::Spacer { priority, .. }
            | Section::Group { priority, .. }
            | Section::Progress { priority, .. }
            | Section::Divider { priority, .. }
            | Section::KeyValue { priority, .. }
            | Section::Badges { priority, .. } => *priority,
        }
    }

    pub fn default_priority(&self) -> u32 {
        self.kind().drop_priority()
    }
}

/// Bridge for density reports: same shape as legacy `PredictedClip`.
pub fn predict_clip(doc: &CanvasDocument, size: WidgetSize) -> crate::layout::PredictedClip {
    let r = pack(doc, size, None);
    crate::layout::PredictedClip {
        will_truncate_sections: r.will_truncate_sections(),
        shown_section_count: r.shown_section_count,
        dropped_section_count: r.dropped_section_count,
        dropped_types: r.dropped_types,
        list_items_shown: r.list_items_shown,
        list_items_total: r.list_items_total,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::schema::{ChartPoint, ChartType, ListItem, MetricItem};

    #[test]
    fn medium_drops_second_chart() {
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
        ];
        let r = pack(&doc, WidgetSize::Medium, None);
        let charts_dropped = r.dropped_types.iter().filter(|t| *t == "chart").count();
        assert!(charts_dropped >= 1, "md should drop at least one chart: {r:?}");
    }
}
