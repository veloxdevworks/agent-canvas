//! Portable layout constants — source of truth for packing and Swift codegen.
//! Values match shipped macOS `ContentClip` behavior.

use serde::Serialize;

use crate::layout::WidgetSize;
use crate::section_meta::{pack_ranks_json, type_defaults_json, SECTION_META};

/// Full layout specification serializable for tooling / conformance.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LayoutSpec {
    pub version: u32,
    pub sizes: Vec<SizeLayoutSpec>,
    pub drop_priorities: serde_json::Value,
    pub pack_ranks: serde_json::Value,
    pub section_kinds: Vec<SectionKindSpec>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SectionKindSpec {
    pub type_name: &'static str,
    pub drop_priority: u32,
    pub pack_rank: u32,
    pub glance_allowed: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SizeLayoutSpec {
    pub size: &'static str,
    pub tile_width: f64,
    pub tile_height: f64,
    pub edge_inset: f64,
    pub section_spacing: f64,
    pub list_item_cap: usize,
    pub max_charts: usize,
    pub max_metrics: usize,
    pub max_text_chars: usize,
    pub list_row_height: f64,
    pub list_title_height: f64,
    pub chart_plot_height: f64,
    pub chart_height_scale: f64,
    pub metrics_height: f64,
    pub header_height_no_subtitle: f64,
    pub header_height_with_subtitle: f64,
    pub text_height: f64,
    pub image_height: f64,
    pub spacer_height: f64,
    pub progress_height: f64,
    pub divider_height: f64,
    pub key_value_row_height: f64,
    pub badges_height: f64,
    pub title_chrome_height: f64,
    pub overflow_line_height: f64,
    pub timestamp_height: f64,
}

impl WidgetSize {
    pub fn layout_spec(self) -> SizeLayoutSpec {
        match self {
            WidgetSize::Small => SizeLayoutSpec {
                size: "sm",
                tile_width: 170.0,
                tile_height: 170.0,
                edge_inset: 12.0,
                section_spacing: 5.0,
                list_item_cap: 5,
                max_charts: 0,
                max_metrics: 2,
                max_text_chars: 80,
                list_row_height: 16.0,
                list_title_height: 14.0,
                chart_plot_height: 36.0,
                chart_height_scale: 0.9,
                metrics_height: 26.0,
                header_height_no_subtitle: 16.0,
                header_height_with_subtitle: 24.0,
                text_height: 26.0,
                image_height: 16.0,
                spacer_height: 4.0,
                progress_height: 18.0,
                divider_height: 8.0,
                key_value_row_height: 16.0,
                badges_height: 20.0,
                title_chrome_height: 16.0,
                overflow_line_height: 12.0,
                timestamp_height: 11.0,
            },
            WidgetSize::Medium => SizeLayoutSpec {
                size: "md",
                tile_width: 364.0,
                tile_height: 170.0,
                edge_inset: 10.0,
                section_spacing: 4.0,
                list_item_cap: 6,
                max_charts: 1,
                max_metrics: 4,
                max_text_chars: 160,
                list_row_height: 26.0,
                list_title_height: 14.0,
                chart_plot_height: 40.0,
                chart_height_scale: 0.85,
                metrics_height: 26.0,
                header_height_no_subtitle: 16.0,
                header_height_with_subtitle: 26.0,
                text_height: 34.0,
                image_height: 16.0,
                spacer_height: 4.0,
                progress_height: 20.0,
                divider_height: 8.0,
                key_value_row_height: 18.0,
                badges_height: 22.0,
                title_chrome_height: 16.0,
                overflow_line_height: 12.0,
                timestamp_height: 11.0,
            },
            WidgetSize::Large => SizeLayoutSpec {
                size: "lg",
                tile_width: 364.0,
                tile_height: 382.0,
                edge_inset: 14.0,
                section_spacing: 5.0,
                list_item_cap: 10,
                max_charts: 2,
                max_metrics: 4,
                max_text_chars: 320,
                list_row_height: 28.0,
                list_title_height: 14.0,
                chart_plot_height: 72.0,
                chart_height_scale: 1.0,
                metrics_height: 48.0,
                header_height_no_subtitle: 18.0,
                header_height_with_subtitle: 28.0,
                text_height: 34.0,
                image_height: 16.0,
                spacer_height: 4.0,
                progress_height: 22.0,
                divider_height: 10.0,
                key_value_row_height: 20.0,
                badges_height: 24.0,
                title_chrome_height: 18.0,
                overflow_line_height: 12.0,
                timestamp_height: 11.0,
            },
            WidgetSize::ExtraLarge => SizeLayoutSpec {
                size: "xl",
                tile_width: 748.0,
                tile_height: 382.0,
                edge_inset: 14.0,
                section_spacing: 5.0,
                list_item_cap: 14,
                max_charts: 2,
                max_metrics: 4,
                max_text_chars: 480,
                list_row_height: 28.0,
                list_title_height: 14.0,
                chart_plot_height: 84.0,
                chart_height_scale: 1.0,
                metrics_height: 48.0,
                header_height_no_subtitle: 18.0,
                header_height_with_subtitle: 28.0,
                text_height: 34.0,
                image_height: 16.0,
                spacer_height: 4.0,
                progress_height: 22.0,
                divider_height: 10.0,
                key_value_row_height: 20.0,
                badges_height: 24.0,
                title_chrome_height: 18.0,
                overflow_line_height: 12.0,
                timestamp_height: 11.0,
            },
        }
    }
}

pub fn layout_spec() -> LayoutSpec {
    LayoutSpec {
        version: 1,
        sizes: WidgetSize::ALL
            .iter()
            .copied()
            .map(WidgetSize::layout_spec)
            .collect(),
        drop_priorities: type_defaults_json(),
        pack_ranks: pack_ranks_json(),
        section_kinds: SECTION_META
            .iter()
            .map(|m| SectionKindSpec {
                type_name: m.type_name,
                drop_priority: m.drop_priority,
                pack_rank: m.pack_rank,
                glance_allowed: m.glance_allowed,
            })
            .collect(),
    }
}

/// Emit Swift source for `LayoutSpec.generated.swift`.
pub fn generate_swift_layout_spec() -> String {
    let mut out = String::new();
    out.push_str("// GENERATED by agent-canvas-core — do not edit by hand.\n");
    out.push_str("// Regenerate: cargo test -p agent-canvas-core layout_spec::tests::swift_matches_committed -- --ignored\n");
    out.push_str("// or: just gen-layout-spec\n\n");
    out.push_str("import CoreGraphics\n\n");
    out.push_str("/// Portable layout constants from Rust `layout_spec`.\n");
    out.push_str("enum LayoutSpec {\n");
    out.push_str("    static let version: Int = 1\n\n");

    // Drop priorities
    out.push_str("    static let dropPriority: [String: Int] = [\n");
    for m in SECTION_META {
        out.push_str(&format!(
            "        \"{}\": {},\n",
            m.type_name, m.drop_priority
        ));
    }
    out.push_str("    ]\n\n");

    out.push_str("    static let packRank: [String: Int] = [\n");
    for m in SECTION_META {
        out.push_str(&format!("        \"{}\": {},\n", m.type_name, m.pack_rank));
    }
    out.push_str("    ]\n\n");

    out.push_str("    struct Size {\n");
    out.push_str("        let tileWidth: CGFloat\n");
    out.push_str("        let tileHeight: CGFloat\n");
    out.push_str("        let edgeInset: CGFloat\n");
    out.push_str("        let sectionSpacing: CGFloat\n");
    out.push_str("        let listItemCap: Int\n");
    out.push_str("        let maxCharts: Int\n");
    out.push_str("        let maxMetrics: Int\n");
    out.push_str("        let maxTextChars: Int\n");
    out.push_str("        let listRowHeight: CGFloat\n");
    out.push_str("        let listTitleHeight: CGFloat\n");
    out.push_str("        let chartPlotHeight: CGFloat\n");
    out.push_str("        let chartHeightScale: CGFloat\n");
    out.push_str("        let metricsHeight: CGFloat\n");
    out.push_str("        let headerHeightNoSubtitle: CGFloat\n");
    out.push_str("        let headerHeightWithSubtitle: CGFloat\n");
    out.push_str("        let textHeight: CGFloat\n");
    out.push_str("        let imageHeight: CGFloat\n");
    out.push_str("        let spacerHeight: CGFloat\n");
    out.push_str("        let progressHeight: CGFloat\n");
    out.push_str("        let dividerHeight: CGFloat\n");
    out.push_str("        let keyValueRowHeight: CGFloat\n");
    out.push_str("        let badgesHeight: CGFloat\n");
    out.push_str("        let titleChromeHeight: CGFloat\n");
    out.push_str("        let overflowLineHeight: CGFloat\n");
    out.push_str("        let timestampHeight: CGFloat\n");
    out.push_str("    }\n\n");

    out.push_str("    static func size(_ s: CanvasSize) -> Size {\n");
    out.push_str("        switch s {\n");
    for ws in WidgetSize::ALL {
        let spec = ws.layout_spec();
        let case = match ws {
            WidgetSize::Small => "sm",
            WidgetSize::Medium => "md",
            WidgetSize::Large => "lg",
            WidgetSize::ExtraLarge => "xl",
        };
        out.push_str(&format!("        case .{case}:\n"));
        out.push_str("            return Size(\n");
        out.push_str(&format!("                tileWidth: {},\n", spec.tile_width));
        out.push_str(&format!("                tileHeight: {},\n", spec.tile_height));
        out.push_str(&format!("                edgeInset: {},\n", spec.edge_inset));
        out.push_str(&format!(
            "                sectionSpacing: {},\n",
            spec.section_spacing
        ));
        out.push_str(&format!(
            "                listItemCap: {},\n",
            spec.list_item_cap
        ));
        out.push_str(&format!("                maxCharts: {},\n", spec.max_charts));
        out.push_str(&format!(
            "                maxMetrics: {},\n",
            spec.max_metrics
        ));
        out.push_str(&format!(
            "                maxTextChars: {},\n",
            spec.max_text_chars
        ));
        out.push_str(&format!(
            "                listRowHeight: {},\n",
            spec.list_row_height
        ));
        out.push_str(&format!(
            "                listTitleHeight: {},\n",
            spec.list_title_height
        ));
        out.push_str(&format!(
            "                chartPlotHeight: {},\n",
            spec.chart_plot_height
        ));
        out.push_str(&format!(
            "                chartHeightScale: {},\n",
            spec.chart_height_scale
        ));
        out.push_str(&format!(
            "                metricsHeight: {},\n",
            spec.metrics_height
        ));
        out.push_str(&format!(
            "                headerHeightNoSubtitle: {},\n",
            spec.header_height_no_subtitle
        ));
        out.push_str(&format!(
            "                headerHeightWithSubtitle: {},\n",
            spec.header_height_with_subtitle
        ));
        out.push_str(&format!("                textHeight: {},\n", spec.text_height));
        out.push_str(&format!(
            "                imageHeight: {},\n",
            spec.image_height
        ));
        out.push_str(&format!(
            "                spacerHeight: {},\n",
            spec.spacer_height
        ));
        out.push_str(&format!(
            "                progressHeight: {},\n",
            spec.progress_height
        ));
        out.push_str(&format!(
            "                dividerHeight: {},\n",
            spec.divider_height
        ));
        out.push_str(&format!(
            "                keyValueRowHeight: {},\n",
            spec.key_value_row_height
        ));
        out.push_str(&format!(
            "                badgesHeight: {},\n",
            spec.badges_height
        ));
        out.push_str(&format!(
            "                titleChromeHeight: {},\n",
            spec.title_chrome_height
        ));
        out.push_str(&format!(
            "                overflowLineHeight: {},\n",
            spec.overflow_line_height
        ));
        out.push_str(&format!(
            "                timestampHeight: {}\n",
            spec.timestamp_height
        ));
        out.push_str("            )\n");
    }
    out.push_str("        }\n");
    out.push_str("    }\n");
    out.push_str("}\n");
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn sm_has_no_charts() {
        assert_eq!(WidgetSize::Small.layout_spec().max_charts, 0);
    }

    #[test]
    fn md_list_packs_constants() {
        let s = WidgetSize::Medium.layout_spec();
        assert_eq!(s.list_row_height, 26.0);
        assert_eq!(s.max_charts, 1);
    }

    fn committed_swift_path() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../platforms/macos/Shared/LayoutSpec.generated.swift")
    }

    #[test]
    fn swift_matches_committed() {
        let path = committed_swift_path();
        let generated = generate_swift_layout_spec();
        if !path.exists() {
            // First run / CI without generated file — write via ignored test.
            eprintln!("missing {}; run just gen-layout-spec", path.display());
        }
        let committed = std::fs::read_to_string(&path).unwrap_or_default();
        assert_eq!(
            committed, generated,
            "LayoutSpec.generated.swift out of date — run: just gen-layout-spec"
        );
    }
}
