//! Named compiled canvas identities: `one` / `two` / `three`.
//!
//! Size is **not** part of the id. The user picks a WidgetKit family when placing
//! the widget. Old size-first ids (`sm-one`, `md-two`, …) and slot-first ids
//! (`one-sm`) parse as **aliases** of the definition for one release.

use serde::{Deserialize, Serialize};

use crate::error::{Error, Result};
use crate::layout::WidgetSize;

/// Slot / compiled definition (three parallel surfaces).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CanvasSlot {
    One,
    Two,
    Three,
}

impl CanvasSlot {
    pub const ALL: [CanvasSlot; 3] = [CanvasSlot::One, CanvasSlot::Two, CanvasSlot::Three];

    pub fn as_str(self) -> &'static str {
        match self {
            CanvasSlot::One => "one",
            CanvasSlot::Two => "two",
            CanvasSlot::Three => "three",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "one" | "1" => Some(CanvasSlot::One),
            "two" | "2" => Some(CanvasSlot::Two),
            "three" | "3" => Some(CanvasSlot::Three),
            _ => None,
        }
    }
}

/// Result of parsing a canvas argument: definition plus optional size hint.
///
/// Size comes from a legacy alias (`sm-one`) or an explicit MCP `size` arg —
/// never from the canonical id (`one`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ParsedCanvas {
    pub id: CanvasId,
    pub alias_size: Option<WidgetSize>,
}

/// Stable agent address: compiled definition only (`one`, `two`, `three`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct CanvasId {
    pub slot: CanvasSlot,
}

impl CanvasId {
    pub const ALL: [CanvasId; 3] = [
        CanvasId {
            slot: CanvasSlot::One,
        },
        CanvasId {
            slot: CanvasSlot::Two,
        },
        CanvasId {
            slot: CanvasSlot::Three,
        },
    ];

    pub fn new(slot: CanvasSlot) -> Self {
        Self { slot }
    }

    /// Wire id: `one`, `two`, `three`.
    pub fn as_str(self) -> &'static str {
        self.slot.as_str()
    }

    pub fn file_name(self) -> String {
        format!("{}.json", self.as_str())
    }

    /// WidgetKit kind — must match Swift `StaticConfiguration` kinds.
    pub fn widget_kind(self) -> String {
        format!("AgentCanvas.{}", self.as_str())
    }

    /// Legacy size-baked filenames for this definition (`sm-one.json`, …).
    pub fn legacy_file_names(self) -> [&'static str; 4] {
        match self.slot {
            CanvasSlot::One => ["sm-one.json", "md-one.json", "lg-one.json", "xl-one.json"],
            CanvasSlot::Two => ["sm-two.json", "md-two.json", "lg-two.json", "xl-two.json"],
            CanvasSlot::Three => [
                "sm-three.json",
                "md-three.json",
                "lg-three.json",
                "xl-three.json",
            ],
        }
    }

    /// Legacy size-first ids for this definition (`sm-one`, …).
    pub fn legacy_ids(self) -> [&'static str; 4] {
        match self.slot {
            CanvasSlot::One => ["sm-one", "md-one", "lg-one", "xl-one"],
            CanvasSlot::Two => ["sm-two", "md-two", "lg-two", "xl-two"],
            CanvasSlot::Three => ["sm-three", "md-three", "lg-three", "xl-three"],
        }
    }

    pub fn parse(s: &str) -> Result<Self> {
        Ok(Self::parse_full(s)?.id)
    }

    /// Parse a canvas argument, keeping a size hint from a legacy alias.
    pub fn parse_full(s: &str) -> Result<ParsedCanvas> {
        let raw = s.trim().to_ascii_lowercase().replace('_', "-");
        if raw.is_empty() {
            return Err(Error::UnknownCanvas(
                "empty canvas id (expected one|two|three, or alias sm-one)".into(),
            ));
        }

        if let Some(slot) = CanvasSlot::parse(&raw) {
            return Ok(ParsedCanvas {
                id: CanvasId::new(slot),
                alias_size: None,
            });
        }

        if let Some((left, right)) = raw.split_once('-') {
            if let (Some(size), Some(slot)) =
                (WidgetSize::parse_short(left), CanvasSlot::parse(right))
            {
                return Ok(ParsedCanvas {
                    id: CanvasId::new(slot),
                    alias_size: Some(size),
                });
            }
            if let (Some(slot), Some(size)) =
                (CanvasSlot::parse(left), WidgetSize::parse_short(right))
            {
                return Ok(ParsedCanvas {
                    id: CanvasId::new(slot),
                    alias_size: Some(size),
                });
            }
        }

        Err(Error::UnknownCanvas(format!(
            "{s} (expected one|two|three, or legacy alias sm|md|lg|xl-one|two|three)"
        )))
    }
}

impl std::fmt::Display for CanvasId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

impl Serialize for CanvasId {
    fn serialize<S: serde::Serializer>(
        &self,
        serializer: S,
    ) -> std::result::Result<S::Ok, S::Error> {
        serializer.serialize_str(self.as_str())
    }
}

impl<'de> Deserialize<'de> for CanvasId {
    fn deserialize<D: serde::Deserializer<'de>>(
        deserializer: D,
    ) -> std::result::Result<Self, D::Error> {
        let s = String::deserialize(deserializer)?;
        CanvasId::parse(&s).map_err(serde::de::Error::custom)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_canonical_definition() {
        let id = CanvasId::parse("one").unwrap();
        assert_eq!(id.slot, CanvasSlot::One);
        assert_eq!(id.as_str(), "one");
        assert_eq!(id.widget_kind(), "AgentCanvas.one");
        assert_eq!(id.file_name(), "one.json");
        assert!(CanvasId::parse_full("one").unwrap().alias_size.is_none());
    }

    #[test]
    fn parse_size_first_alias() {
        let parsed = CanvasId::parse_full("sm-one").unwrap();
        assert_eq!(parsed.id.as_str(), "one");
        assert_eq!(parsed.alias_size, Some(WidgetSize::Small));
        assert_eq!(parsed.id.widget_kind(), "AgentCanvas.one");
    }

    #[test]
    fn parse_slot_first_alias() {
        let parsed = CanvasId::parse_full("two-md").unwrap();
        assert_eq!(parsed.id.as_str(), "two");
        assert_eq!(parsed.alias_size, Some(WidgetSize::Medium));
    }

    #[test]
    fn parse_all_legacy_aliases() {
        for id in CanvasId::ALL {
            for (legacy, size) in id.legacy_ids().iter().zip(WidgetSize::ALL) {
                let parsed = CanvasId::parse_full(legacy).unwrap();
                assert_eq!(parsed.id, id);
                assert_eq!(parsed.alias_size, Some(size));
            }
        }
    }

    #[test]
    fn all_three_unique() {
        let mut set = std::collections::HashSet::new();
        for id in CanvasId::ALL {
            assert!(set.insert(id.as_str()));
        }
        assert_eq!(set.len(), 3);
    }

    #[test]
    fn unknown_id_errors() {
        let err = CanvasId::parse("four").unwrap_err().to_string();
        assert!(err.contains("one|two|three") || err.contains("unknown"));
    }
}
