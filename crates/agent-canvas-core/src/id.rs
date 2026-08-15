//! Named compiled canvas identities: `one` through `twelve`.
//!
//! Size is **not** part of the id. The user picks a WidgetKit family when placing
//! the widget. Old size-first ids (`sm-one`, `md-two`, …) and slot-first ids
//! (`one-sm`) parse as **aliases** of the first three definitions only — the
//! previous model was 4 sizes × 3 slots. There are no `sm-four` aliases.

use serde::{Deserialize, Serialize};

use crate::error::{Error, Result};
use crate::layout::WidgetSize;

/// Help string for MCP / errors: twelve compiled ids; aliases only for one–three.
pub const ID_FORMAT_HELP: &str = "one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve \
     (aliases for one–three only: sm-one, md-two, …)";

/// Slot / compiled definition (twelve parallel surfaces).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CanvasSlot {
    One,
    Two,
    Three,
    Four,
    Five,
    Six,
    Seven,
    Eight,
    Nine,
    Ten,
    Eleven,
    Twelve,
}

impl CanvasSlot {
    pub const ALL: [CanvasSlot; 12] = [
        CanvasSlot::One,
        CanvasSlot::Two,
        CanvasSlot::Three,
        CanvasSlot::Four,
        CanvasSlot::Five,
        CanvasSlot::Six,
        CanvasSlot::Seven,
        CanvasSlot::Eight,
        CanvasSlot::Nine,
        CanvasSlot::Ten,
        CanvasSlot::Eleven,
        CanvasSlot::Twelve,
    ];

    pub const NAMES: [&str; 12] = [
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
        "twelve",
    ];

    pub fn as_str(self) -> &'static str {
        Self::NAMES[self.index()]
    }

    pub fn index(self) -> usize {
        Self::ALL
            .iter()
            .position(|&s| s == self)
            .expect("CanvasSlot::ALL is exhaustive")
    }

    /// Old 4×3 model only had size-baked files for one / two / three.
    pub fn has_legacy_aliases(self) -> bool {
        matches!(self, CanvasSlot::One | CanvasSlot::Two | CanvasSlot::Three)
    }

    /// Cycle the three themed demo recipes across all twelve ids.
    pub fn themed_recipe(self) -> CanvasSlot {
        Self::ALL[self.index() % 3]
    }

    pub fn parse(s: &str) -> Option<Self> {
        let raw = s.trim().to_ascii_lowercase();
        if let Some(i) = Self::NAMES.iter().position(|n| *n == raw) {
            return Some(Self::ALL[i]);
        }
        if let Ok(n) = raw.parse::<usize>() {
            if (1..=12).contains(&n) {
                return Some(Self::ALL[n - 1]);
            }
        }
        None
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

/// Stable agent address: compiled definition only (`one` … `twelve`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct CanvasId {
    pub slot: CanvasSlot,
}

impl CanvasId {
    pub const ALL: [CanvasId; 12] = [
        CanvasId {
            slot: CanvasSlot::One,
        },
        CanvasId {
            slot: CanvasSlot::Two,
        },
        CanvasId {
            slot: CanvasSlot::Three,
        },
        CanvasId {
            slot: CanvasSlot::Four,
        },
        CanvasId {
            slot: CanvasSlot::Five,
        },
        CanvasId {
            slot: CanvasSlot::Six,
        },
        CanvasId {
            slot: CanvasSlot::Seven,
        },
        CanvasId {
            slot: CanvasSlot::Eight,
        },
        CanvasId {
            slot: CanvasSlot::Nine,
        },
        CanvasId {
            slot: CanvasSlot::Ten,
        },
        CanvasId {
            slot: CanvasSlot::Eleven,
        },
        CanvasId {
            slot: CanvasSlot::Twelve,
        },
    ];

    pub fn new(slot: CanvasSlot) -> Self {
        Self { slot }
    }

    /// Wire id: `one` … `twelve`.
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

    /// Legacy size-baked filenames (`sm-one.json`, …). Empty for four–twelve.
    pub fn legacy_file_names(self) -> &'static [&'static str] {
        match self.slot {
            CanvasSlot::One => &["sm-one.json", "md-one.json", "lg-one.json", "xl-one.json"],
            CanvasSlot::Two => &["sm-two.json", "md-two.json", "lg-two.json", "xl-two.json"],
            CanvasSlot::Three => &[
                "sm-three.json",
                "md-three.json",
                "lg-three.json",
                "xl-three.json",
            ],
            _ => &[],
        }
    }

    /// Legacy size-first ids (`sm-one`, …). Empty for four–twelve.
    pub fn legacy_ids(self) -> &'static [&'static str] {
        match self.slot {
            CanvasSlot::One => &["sm-one", "md-one", "lg-one", "xl-one"],
            CanvasSlot::Two => &["sm-two", "md-two", "lg-two", "xl-two"],
            CanvasSlot::Three => &["sm-three", "md-three", "lg-three", "xl-three"],
            _ => &[],
        }
    }

    pub fn parse(s: &str) -> Result<Self> {
        Ok(Self::parse_full(s)?.id)
    }

    /// Parse a canvas argument, keeping a size hint from a legacy alias.
    pub fn parse_full(s: &str) -> Result<ParsedCanvas> {
        let raw = s.trim().to_ascii_lowercase().replace('_', "-");
        if raw.is_empty() {
            return Err(Error::UnknownCanvas(format!(
                "empty canvas id (expected {ID_FORMAT_HELP})"
            )));
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
                if slot.has_legacy_aliases() {
                    return Ok(ParsedCanvas {
                        id: CanvasId::new(slot),
                        alias_size: Some(size),
                    });
                }
            }
            if let (Some(slot), Some(size)) =
                (CanvasSlot::parse(left), WidgetSize::parse_short(right))
            {
                if slot.has_legacy_aliases() {
                    return Ok(ParsedCanvas {
                        id: CanvasId::new(slot),
                        alias_size: Some(size),
                    });
                }
            }
        }

        Err(Error::UnknownCanvas(format!(
            "{s} (expected {ID_FORMAT_HELP})"
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
    fn parse_twelve_and_numeric() {
        let twelve = CanvasId::parse("twelve").unwrap();
        assert_eq!(twelve.as_str(), "twelve");
        assert_eq!(twelve.widget_kind(), "AgentCanvas.twelve");
        assert_eq!(twelve.file_name(), "twelve.json");
        assert_eq!(CanvasId::parse("12").unwrap().as_str(), "twelve");
        assert_eq!(CanvasId::parse("4").unwrap().as_str(), "four");
        assert_eq!(CanvasId::parse("FOUR").unwrap().as_str(), "four");
        assert!(CanvasId::parse_full("twelve").unwrap().alias_size.is_none());
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
            if !id.slot.has_legacy_aliases() {
                assert!(id.legacy_ids().is_empty());
                assert!(id.legacy_file_names().is_empty());
                continue;
            }
            for (legacy, size) in id.legacy_ids().iter().zip(WidgetSize::ALL) {
                let parsed = CanvasId::parse_full(legacy).unwrap();
                assert_eq!(parsed.id, id);
                assert_eq!(parsed.alias_size, Some(size));
            }
        }
    }

    #[test]
    fn reject_invented_size_aliases() {
        for raw in ["sm-four", "md-twelve", "four-sm", "twelve-xl"] {
            let err = CanvasId::parse(raw).unwrap_err().to_string();
            assert!(
                err.contains("unknown") || err.contains("expected"),
                "{raw} should not parse: {err}"
            );
        }
    }

    #[test]
    fn all_twelve_unique() {
        let mut set = std::collections::HashSet::new();
        for id in CanvasId::ALL {
            assert!(set.insert(id.as_str()));
        }
        assert_eq!(set.len(), 12);
        assert_eq!(CanvasId::ALL.len(), 12);
        assert_eq!(CanvasId::ALL.last().unwrap().as_str(), "twelve");
    }

    #[test]
    fn unknown_id_errors() {
        let err = CanvasId::parse("thirteen").unwrap_err().to_string();
        assert!(err.contains("unknown") || err.contains("expected"));
        assert!(CanvasId::parse("0").is_err());
        assert!(CanvasId::parse("13").is_err());
    }
}
