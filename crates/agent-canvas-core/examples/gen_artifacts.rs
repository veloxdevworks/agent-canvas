
fn main() {
    let s = agent_canvas_core::generate_canvas_schema_string();
    std::fs::write("schema/canvas.schema.json", s).unwrap();
    let swift = agent_canvas_core::generate_swift_layout_spec();
    std::fs::write("platforms/macos/Shared/LayoutSpec.generated.swift", swift).unwrap();
    println!("wrote schema + LayoutSpec.generated.swift");
}
