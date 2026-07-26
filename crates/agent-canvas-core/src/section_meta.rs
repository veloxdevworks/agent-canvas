//! Single source of truth for section kind metadata.
//!
//! **Drop priority** (lower = keep first when clipping by importance) and
//! **pack rank** (lower = allocate height first) are distinct. Pack order
//! matches the shipped Swift `ContentClip.packRank` so charts shrink into
//! leftover space after lists claim rows.

use serde::Serialize;
use serde_json::{json, Map, Value};

/// Known section kinds in schema v1 (+ expressiveness extensions).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum SectionKind {
    Header,
    Text,
    Metrics,
    Chart,
    List,
    Image,
    Spacer,
    Group,
    Progress,
    Divider,
    KeyValue,
    Badges,
}

/// Metadata for one section kind.
#[derive(Debug, Clone, Copy)]
pub struct SectionMeta {
    pub kind: SectionKind,
    pub type_name: &'static str,
    /// Lower = more important when ranking which sections to keep.
    pub drop_priority: u32,
    /// Lower = pack (allocate height) earlier. Matches Swift ContentClip.
    pub pack_rank: u32,
    /// Allowed in glance `sections` (false → detail-only for now).
    pub glance_allowed: bool,
}

/// Canonical table — add new kinds here only.
pub const SECTION_META: &[SectionMeta] = &[
    SectionMeta {
        kind: SectionKind::Header,
        type_name: "header",
        drop_priority: 10,
        pack_rank: 0,
        glance_allowed: true,
    },
    SectionMeta {
        kind: SectionKind::Metrics,
        type_name: "metrics",
        drop_priority: 20,
        pack_rank: 1,
        glance_allowed: true,
    },
    SectionMeta {
        kind: SectionKind::List,
        type_name: "list",
        drop_priority: 40,
        pack_rank: 2,
        glance_allowed: true,
    },
    SectionMeta {
        kind: SectionKind::Chart,
        type_name: "chart",
        drop_priority: 30,
        pack_rank: 3,
        glance_allowed: true,
    },
    SectionMeta {
        kind: SectionKind::Text,
        type_name: "text",
        drop_priority: 50,
        pack_rank: 4,
        glance_allowed: true,
    },
    SectionMeta {
        kind: SectionKind::Image,
        type_name: "image",
        drop_priority: 60,
        pack_rank: 5,
        glance_allowed: true,
    },
    SectionMeta {
        kind: SectionKind::Spacer,
        type_name: "spacer",
        drop_priority: 70,
        pack_rank: 6,
        glance_allowed: true,
    },
    SectionMeta {
        kind: SectionKind::Progress,
        type_name: "progress",
        drop_priority: 45,
        pack_rank: 4,
        glance_allowed: true,
    },
    SectionMeta {
        kind: SectionKind::Divider,
        type_name: "divider",
        drop_priority: 75,
        pack_rank: 6,
        glance_allowed: true,
    },
    SectionMeta {
        kind: SectionKind::KeyValue,
        type_name: "keyValue",
        drop_priority: 42,
        pack_rank: 2,
        glance_allowed: true,
    },
    SectionMeta {
        kind: SectionKind::Badges,
        type_name: "badges",
        drop_priority: 48,
        pack_rank: 4,
        glance_allowed: true,
    },
    // Group is detail-only until glance packing is proven.
    SectionMeta {
        kind: SectionKind::Group,
        type_name: "group",
        drop_priority: 55,
        pack_rank: 2,
        glance_allowed: false,
    },
];

impl SectionKind {
    pub fn meta(self) -> &'static SectionMeta {
        SECTION_META
            .iter()
            .find(|m| m.kind == self)
            .expect("SECTION_META incomplete")
    }

    pub fn from_type_name(name: &str) -> Option<Self> {
        SECTION_META
            .iter()
            .find(|m| m.type_name == name)
            .map(|m| m.kind)
    }

    pub fn type_name(self) -> &'static str {
        self.meta().type_name
    }

    pub fn drop_priority(self) -> u32 {
        self.meta().drop_priority
    }

    pub fn pack_rank(self) -> u32 {
        self.meta().pack_rank
    }

    pub fn glance_allowed(self) -> bool {
        self.meta().glance_allowed
    }
}

/// `typeDefaults` object for `get_layout_guide` (drop priorities).
pub fn type_defaults_json() -> Value {
    let mut map = Map::new();
    for m in SECTION_META {
        map.insert(m.type_name.to_string(), json!(m.drop_priority));
    }
    Value::Object(map)
}

/// Pack-rank object for layout guide / generated specs.
pub fn pack_ranks_json() -> Value {
    let mut map = Map::new();
    for m in SECTION_META {
        map.insert(m.type_name.to_string(), json!(m.pack_rank));
    }
    Value::Object(map)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn list_packs_before_chart() {
        assert!(SectionKind::List.pack_rank() < SectionKind::Chart.pack_rank());
    }

    #[test]
    fn chart_drops_before_list() {
        // Keep chart over list when ranking by importance (drop priority).
        assert!(SectionKind::Chart.drop_priority() < SectionKind::List.drop_priority());
    }

    #[test]
    fn group_not_in_glance() {
        assert!(!SectionKind::Group.glance_allowed());
    }

    #[test]
    fn all_kinds_unique_names() {
        let mut names: Vec<_> = SECTION_META.iter().map(|m| m.type_name).collect();
        names.sort_unstable();
        names.dedup();
        assert_eq!(names.len(), SECTION_META.len());
    }
}
