//! Cross-language packing conformance against `schema/conformance/*.json`.

#[cfg(test)]
mod tests {
    use serde::Deserialize;

    use crate::layout::WidgetSize;
    use crate::packer::pack;
    use crate::schema::CanvasDocument;

    #[derive(Debug, Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct ConformanceCase {
        fixture: String,
        size: String,
        expected: Expected,
    }

    #[derive(Debug, Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Expected {
        shown_indices: Vec<usize>,
        dropped_types: Vec<String>,
        truncated: bool,
        list_items_shown: usize,
        list_items_total: usize,
        chart_height_scale: f64,
        shown_section_count: usize,
        dropped_section_count: usize,
        #[serde(default)]
        cover: bool,
    }

    fn schema_root() -> std::path::PathBuf {
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../schema")
    }

    #[test]
    fn conformance_goldens() {
        let root = schema_root();
        let dir = root.join("conformance");
        let mut cases = 0usize;
        for entry in std::fs::read_dir(&dir).expect("schema/conformance") {
            let entry = entry.unwrap();
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("json") {
                continue;
            }
            let raw = std::fs::read_to_string(&path).unwrap();
            let case: ConformanceCase =
                serde_json::from_str(&raw).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
            let fixture_path = root.join(&case.fixture);
            let doc_raw = std::fs::read_to_string(&fixture_path)
                .unwrap_or_else(|e| panic!("{}: {e}", fixture_path.display()));
            let doc: CanvasDocument = serde_json::from_str(&doc_raw).unwrap();
            let size = WidgetSize::parse(&case.size).expect("size");
            let got = pack(&doc, size, None);
            assert_eq!(
                got.shown_indices,
                case.expected.shown_indices,
                "{} shownIndices",
                path.display()
            );
            assert_eq!(
                got.dropped_types,
                case.expected.dropped_types,
                "{} droppedTypes",
                path.display()
            );
            assert_eq!(
                got.truncated,
                case.expected.truncated,
                "{} truncated",
                path.display()
            );
            assert_eq!(
                got.list_items_shown,
                case.expected.list_items_shown,
                "{} listItemsShown",
                path.display()
            );
            assert_eq!(
                got.list_items_total,
                case.expected.list_items_total,
                "{} listItemsTotal",
                path.display()
            );
            assert!(
                (got.chart_height_scale - case.expected.chart_height_scale).abs() < 1e-9,
                "{} chartHeightScale {} vs {}",
                path.display(),
                got.chart_height_scale,
                case.expected.chart_height_scale
            );
            assert_eq!(
                got.shown_section_count,
                case.expected.shown_section_count,
                "{} shownSectionCount",
                path.display()
            );
            assert_eq!(
                got.dropped_section_count,
                case.expected.dropped_section_count,
                "{} droppedSectionCount",
                path.display()
            );
            assert_eq!(got.cover, case.expected.cover, "{} cover", path.display());
            cases += 1;
        }
        assert!(cases >= 8, "expected conformance cases, got {cases}");
    }
}
