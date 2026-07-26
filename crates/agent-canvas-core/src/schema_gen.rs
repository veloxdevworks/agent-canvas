//! Generate `schema/canvas.schema.json` from Rust models / constants.
//!
//! Uses a hand-built JSON Schema (not raw schemars output) so we keep
//! curated descriptions, `additionalProperties: false`, and `$defs` shape.
//! Regenerated in tests; commit the result.

use serde_json::{json, Value};

use crate::schema::CanvasDocument;

/// Produce the canonical JSON Schema document.
pub fn generate_canvas_schema() -> Value {
    json!({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://velox.dev/schemas/agent-canvas/v1/canvas.schema.json",
        "title": "AgentCanvasDocument",
        "description": "Declarative content for one Agent Canvas desktop widget (schema version 1). Generated from agent-canvas-core — do not edit by hand; run just gen-schema.",
        "type": "object",
        "required": ["version", "sections"],
        "additionalProperties": false,
        "properties": {
            "version": {
                "type": "integer",
                "const": CanvasDocument::SCHEMA_VERSION
            },
            "updatedAt": {
                "type": "string",
                "format": "date-time",
                "description": "ISO-8601 timestamp; server may overwrite on write."
            },
            "title": {
                "type": "string",
                "maxLength": 120
            },
            "onOpen": {
                "$ref": "#/$defs/action",
                "description": "Action when the user taps the widget tile. Default when omitted: expand (detail window)."
            },
            "sections": {
                "type": "array",
                "maxItems": CanvasDocument::MAX_SECTIONS,
                "items": { "$ref": "#/$defs/glanceSection" },
                "description": "Glance tile sections. type=group is not allowed here (use detail.sections)."
            },
            "detail": {
                "type": "object",
                "additionalProperties": false,
                "description": "Optional richer layout for the expand detail window. Not counted toward glance density. May include group.",
                "properties": {
                    "sections": {
                        "type": "array",
                        "maxItems": CanvasDocument::MAX_DETAIL_SECTIONS,
                        "items": { "$ref": "#/$defs/section" }
                    }
                }
            }
        },
        "$defs": {
            "tone": {
                "type": "string",
                "enum": ["critical", "warning", "success", "info", "muted"],
                "description": "Semantic tone (maps to system colors / Adaptive Cards color)."
            },
            "emphasis": {
                "type": "string",
                "enum": ["strong", "normal", "subtle"],
                "description": "Semantic emphasis (maps to system font weights / Adaptive Cards weight)."
            },
            "action": {
                "oneOf": [
                    {
                        "type": "object",
                        "required": ["type"],
                        "additionalProperties": false,
                        "properties": { "type": { "const": "expand" } }
                    },
                    {
                        "type": "object",
                        "required": ["type", "url"],
                        "additionalProperties": false,
                        "properties": {
                            "type": { "const": "url" },
                            "url": {
                                "type": "string",
                                "minLength": 1,
                                "description": "http, https, or mailto only. No credentials."
                            }
                        }
                    },
                    {
                        "type": "object",
                        "required": ["type", "path"],
                        "additionalProperties": false,
                        "properties": {
                            "type": { "const": "file" },
                            "path": {
                                "type": "string",
                                "minLength": 1,
                                "description": "Absolute local path. Host reveals in Finder; does not launch."
                            }
                        }
                    },
                    {
                        "type": "object",
                        "required": ["type"],
                        "additionalProperties": false,
                        "properties": { "type": { "const": "noop" } }
                    }
                ]
            },
            "priority": {
                "type": "integer",
                "minimum": 0,
                "description": "Lower = more important when the widget clips to size budget."
            },
            "glanceSection": {
                "oneOf": [
                    { "$ref": "#/$defs/header" },
                    { "$ref": "#/$defs/text" },
                    { "$ref": "#/$defs/metrics" },
                    { "$ref": "#/$defs/chart" },
                    { "$ref": "#/$defs/list" },
                    { "$ref": "#/$defs/image" },
                    { "$ref": "#/$defs/spacer" },
                    { "$ref": "#/$defs/progress" },
                    { "$ref": "#/$defs/divider" },
                    { "$ref": "#/$defs/keyValue" },
                    { "$ref": "#/$defs/badges" }
                ]
            },
            "section": {
                "oneOf": [
                    { "$ref": "#/$defs/header" },
                    { "$ref": "#/$defs/text" },
                    { "$ref": "#/$defs/metrics" },
                    { "$ref": "#/$defs/chart" },
                    { "$ref": "#/$defs/list" },
                    { "$ref": "#/$defs/image" },
                    { "$ref": "#/$defs/spacer" },
                    { "$ref": "#/$defs/group" },
                    { "$ref": "#/$defs/progress" },
                    { "$ref": "#/$defs/divider" },
                    { "$ref": "#/$defs/keyValue" },
                    { "$ref": "#/$defs/badges" }
                ]
            },
            "header": {
                "type": "object",
                "required": ["type", "text"],
                "additionalProperties": false,
                "properties": {
                    "type": { "const": "header" },
                    "text": { "type": "string", "minLength": 1, "maxLength": 80 },
                    "subtitle": { "type": "string", "maxLength": 120 },
                    "tone": { "$ref": "#/$defs/tone" },
                    "emphasis": { "$ref": "#/$defs/emphasis" },
                    "priority": { "$ref": "#/$defs/priority" }
                }
            },
            "text": {
                "type": "object",
                "required": ["type", "content"],
                "additionalProperties": false,
                "properties": {
                    "type": { "const": "text" },
                    "content": { "type": "string", "minLength": 1, "maxLength": 2000 },
                    "tone": { "$ref": "#/$defs/tone" },
                    "emphasis": { "$ref": "#/$defs/emphasis" },
                    "priority": { "$ref": "#/$defs/priority" }
                }
            },
            "metrics": {
                "type": "object",
                "required": ["type", "items"],
                "additionalProperties": false,
                "properties": {
                    "type": { "const": "metrics" },
                    "items": {
                        "type": "array",
                        "minItems": 1,
                        "maxItems": CanvasDocument::MAX_METRICS,
                        "items": {
                            "type": "object",
                            "required": ["label", "value"],
                            "additionalProperties": false,
                            "properties": {
                                "label": { "type": "string" },
                                "value": { "type": "string" },
                                "trend": { "type": "string" },
                                "tone": { "$ref": "#/$defs/tone" },
                                "emphasis": { "$ref": "#/$defs/emphasis" }
                            }
                        }
                    },
                    "priority": { "$ref": "#/$defs/priority" }
                }
            },
            "chart": {
                "type": "object",
                "required": ["type", "chartType", "data"],
                "additionalProperties": false,
                "properties": {
                    "type": { "const": "chart" },
                    "chartType": {
                        "type": "string",
                        "enum": ["bar", "line", "pie", "gauge"]
                    },
                    "title": { "type": "string" },
                    "data": {
                        "type": "array",
                        "minItems": 1,
                        "maxItems": CanvasDocument::MAX_CHART_POINTS,
                        "items": {
                            "type": "object",
                            "required": ["label", "value"],
                            "additionalProperties": false,
                            "properties": {
                                "label": { "type": "string" },
                                "value": { "type": "number" }
                            }
                        }
                    },
                    "priority": { "$ref": "#/$defs/priority" }
                }
            },
            "list": {
                "type": "object",
                "required": ["type", "items"],
                "additionalProperties": false,
                "properties": {
                    "type": { "const": "list" },
                    "title": { "type": "string" },
                    "items": {
                        "type": "array",
                        "maxItems": CanvasDocument::MAX_LIST_ITEMS,
                        "items": {
                            "type": "object",
                            "required": ["primary"],
                            "additionalProperties": false,
                            "properties": {
                                "primary": { "type": "string" },
                                "secondary": { "type": "string" },
                                "badge": { "type": "string" },
                                "action": { "$ref": "#/$defs/action" },
                                "tone": { "$ref": "#/$defs/tone" },
                                "emphasis": { "$ref": "#/$defs/emphasis" }
                            }
                        }
                    },
                    "priority": { "$ref": "#/$defs/priority" }
                }
            },
            "image": {
                "type": "object",
                "required": ["type", "source"],
                "additionalProperties": false,
                "properties": {
                    "type": { "const": "image" },
                    "source": {
                        "type": "string",
                        "description": "data:image/...;base64,... or file:// under app data. No remote URLs in v1.",
                        "minLength": 1
                    },
                    "url": {
                        "type": "string",
                        "description": "Legacy alias for source."
                    },
                    "caption": { "type": "string" },
                    "priority": { "$ref": "#/$defs/priority" }
                }
            },
            "spacer": {
                "type": "object",
                "required": ["type"],
                "additionalProperties": false,
                "properties": {
                    "type": { "const": "spacer" },
                    "size": {
                        "type": "string",
                        "enum": ["sm", "md", "lg"]
                    },
                    "priority": { "$ref": "#/$defs/priority" }
                }
            },
            "group": {
                "type": "object",
                "required": ["type", "direction", "children"],
                "additionalProperties": false,
                "description": "Flex container. Detail-only (not in glance sections). Depth ≤ 2; children ≤ 6. Atomic for clipping.",
                "properties": {
                    "type": { "const": "group" },
                    "direction": {
                        "type": "string",
                        "enum": ["row", "column"]
                    },
                    "gap": {
                        "type": "string",
                        "enum": ["sm", "md", "lg"]
                    },
                    "align": {
                        "type": "string",
                        "enum": ["start", "center", "end", "stretch"]
                    },
                    "children": {
                        "type": "array",
                        "minItems": 1,
                        "maxItems": CanvasDocument::MAX_GROUP_CHILDREN,
                        "items": { "$ref": "#/$defs/section" }
                    },
                    "weight": { "type": "integer", "minimum": 0 },
                    "priority": { "$ref": "#/$defs/priority" }
                }
            },
            "progress": {
                "type": "object",
                "required": ["type", "value"],
                "additionalProperties": false,
                "description": "Progress bar. On platforms without a native control, degrade to text (e.g. Adaptive Cards).",
                "properties": {
                    "type": { "const": "progress" },
                    "label": { "type": "string" },
                    "value": { "type": "number" },
                    "max": { "type": "number", "exclusiveMinimum": 0 },
                    "tone": { "$ref": "#/$defs/tone" },
                    "priority": { "$ref": "#/$defs/priority" }
                }
            },
            "divider": {
                "type": "object",
                "required": ["type"],
                "additionalProperties": false,
                "properties": {
                    "type": { "const": "divider" },
                    "priority": { "$ref": "#/$defs/priority" }
                }
            },
            "keyValue": {
                "type": "object",
                "required": ["type", "items"],
                "additionalProperties": false,
                "properties": {
                    "type": { "const": "keyValue" },
                    "items": {
                        "type": "array",
                        "minItems": 1,
                        "maxItems": CanvasDocument::MAX_KEY_VALUE,
                        "items": {
                            "type": "object",
                            "required": ["key", "value"],
                            "additionalProperties": false,
                            "properties": {
                                "key": { "type": "string" },
                                "value": { "type": "string" },
                                "tone": { "$ref": "#/$defs/tone" }
                            }
                        }
                    },
                    "priority": { "$ref": "#/$defs/priority" }
                }
            },
            "badges": {
                "type": "object",
                "required": ["type", "items"],
                "additionalProperties": false,
                "properties": {
                    "type": { "const": "badges" },
                    "items": {
                        "type": "array",
                        "minItems": 1,
                        "maxItems": CanvasDocument::MAX_BADGES,
                        "items": {
                            "type": "object",
                            "required": ["text"],
                            "additionalProperties": false,
                            "properties": {
                                "text": { "type": "string" },
                                "tone": { "$ref": "#/$defs/tone" }
                            }
                        }
                    },
                    "priority": { "$ref": "#/$defs/priority" }
                }
            }
        }
    })
}

/// Pretty-printed schema text (trailing newline).
pub fn generate_canvas_schema_string() -> String {
    let mut s = serde_json::to_string_pretty(&generate_canvas_schema()).expect("schema json");
    s.push('\n');
    s
}

#[allow(dead_code)]
pub fn committed_schema_path() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../schema/canvas.schema.json")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn schema_matches_committed() {
        let path = committed_schema_path();
        let generated = generate_canvas_schema_string();
        let committed = std::fs::read_to_string(&path).unwrap_or_default();
        assert_eq!(
            committed, generated,
            "schema/canvas.schema.json out of date — run: just gen-schema"
        );
    }

    #[test]
    fn fixtures_validate() {
        let dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../schema/fixtures");
        for entry in std::fs::read_dir(&dir).expect("fixtures dir") {
            let entry = entry.unwrap();
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("json") {
                continue;
            }
            let raw = std::fs::read_to_string(&path).unwrap();
            let doc: crate::schema::CanvasDocument = serde_json::from_str(&raw)
                .unwrap_or_else(|e| panic!("{}: deserialize {e}", path.display()));
            doc.validate()
                .unwrap_or_else(|e| panic!("{}: validate {e}", path.display()));
        }
    }
}
