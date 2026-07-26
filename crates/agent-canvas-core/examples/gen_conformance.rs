
use agent_canvas_core::{pack, CanvasDocument, WidgetSize};
use serde_json::json;
use std::fs;
use std::path::PathBuf;

fn main() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../schema");
    let fixtures = root.join("fixtures");
    let out_dir = root.join("conformance");
    fs::create_dir_all(&out_dir).unwrap();

    let sizes = [
        WidgetSize::Small,
        WidgetSize::Medium,
        WidgetSize::Large,
        WidgetSize::ExtraLarge,
    ];

    for entry in fs::read_dir(&fixtures).unwrap() {
        let entry = entry.unwrap();
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        let name = path.file_stem().unwrap().to_string_lossy().to_string();
        // Skip empty-ish
        let raw = fs::read_to_string(&path).unwrap();
        let doc: CanvasDocument = match serde_json::from_str(&raw) {
            Ok(d) => d,
            Err(e) => {
                eprintln!("skip {}: {e}", path.display());
                continue;
            }
        };
        for size in sizes {
            let r = pack(&doc, size, None);
            let case = json!({
                "fixture": format!("fixtures/{}.json", name),
                "size": size.short(),
                "expected": {
                    "shownIndices": r.shown_indices,
                    "droppedTypes": r.dropped_types,
                    "truncated": r.truncated,
                    "listItemsShown": r.list_items_shown,
                    "listItemsTotal": r.list_items_total,
                    "chartHeightScale": r.chart_height_scale,
                    "shownSectionCount": r.shown_section_count,
                    "droppedSectionCount": r.dropped_section_count,
                    "cover": r.cover,
                }
            });
            let out = out_dir.join(format!("{}-{}.json", name, size.short()));
            fs::write(&out, serde_json::to_string_pretty(&case).unwrap() + "\n").unwrap();
            println!("wrote {}", out.display());
        }
    }
}
