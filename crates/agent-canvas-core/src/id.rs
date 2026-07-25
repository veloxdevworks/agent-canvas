//! Size-first canvas addresses: `{size}-{slot}` e.g. `sm-one`, `md-two`, `xl-three`.
//!
//! Agents always know both density and slot from the id alone — no multi-instance
//! size ambiguity.

use serde::{Deserialize, Serialize};

use crate::error::{Error, Result};
use crate::layout::WidgetSize;

/// Slot within a size band (three parallel surfaces per size).
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

/// Stable agent address: size first, then slot (`sm-one`, `lg-two`, …).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct CanvasId {
    pub size: WidgetSize,
    pub slot: CanvasSlot,
}

impl CanvasId {
    pub const ALL: [CanvasId; 12] = [
        CanvasId {
            size: WidgetSize::Small,
            slot: CanvasSlot::One,
        },
        CanvasId {
            size: WidgetSize::Small,
            slot: CanvasSlot::Two,
        },
        CanvasId {
            size: WidgetSize::Small,
            slot: CanvasSlot::Three,
        },
        CanvasId {
            size: WidgetSize::Medium,
            slot: CanvasSlot::One,
        },
        CanvasId {
            size: WidgetSize::Medium,
            slot: CanvasSlot::Two,
        },
        CanvasId {
            size: WidgetSize::Medium,
            slot: CanvasSlot::Three,
        },
        CanvasId {
            size: WidgetSize::Large,
            slot: CanvasSlot::One,
        },
        CanvasId {
            size: WidgetSize::Large,
            slot: CanvasSlot::Two,
        },
        CanvasId {
            size: WidgetSize::Large,
            slot: CanvasSlot::Three,
        },
        CanvasId {
            size: WidgetSize::ExtraLarge,
            slot: CanvasSlot::One,
        },
        CanvasId {
            size: WidgetSize::ExtraLarge,
            slot: CanvasSlot::Two,
        },
        CanvasId {
            size: WidgetSize::ExtraLarge,
            slot: CanvasSlot::Three,
        },
    ];

    pub fn new(size: WidgetSize, slot: CanvasSlot) -> Self {
        Self { size, slot }
    }

    /// Wire id: `sm-one`, `md-two`, `lg-three`, `xl-one`, …
    pub fn as_str(self) -> &'static str {
        match (self.size, self.slot) {
            (WidgetSize::Small, CanvasSlot::One) => "sm-one",
            (WidgetSize::Small, CanvasSlot::Two) => "sm-two",
            (WidgetSize::Small, CanvasSlot::Three) => "sm-three",
            (WidgetSize::Medium, CanvasSlot::One) => "md-one",
            (WidgetSize::Medium, CanvasSlot::Two) => "md-two",
            (WidgetSize::Medium, CanvasSlot::Three) => "md-three",
            (WidgetSize::Large, CanvasSlot::One) => "lg-one",
            (WidgetSize::Large, CanvasSlot::Two) => "lg-two",
            (WidgetSize::Large, CanvasSlot::Three) => "lg-three",
            (WidgetSize::ExtraLarge, CanvasSlot::One) => "xl-one",
            (WidgetSize::ExtraLarge, CanvasSlot::Two) => "xl-two",
            (WidgetSize::ExtraLarge, CanvasSlot::Three) => "xl-three",
        }
    }

    pub fn file_name(self) -> String {
        format!("{}.json", self.as_str())
    }

    /// WidgetKit kind — must match Swift `StaticConfiguration` kinds.
    pub fn widget_kind(self) -> String {
        format!("AgentCanvas.{}", self.as_str())
    }

    pub fn parse(s: &str) -> Result<Self> {
        let raw = s.trim().to_ascii_lowercase().replace('_', "-");
        // Prefer size-first: sm-one
        if let Some((size_s, slot_s)) = raw.split_once('-') {
            if let (Some(size), Some(slot)) =
                (WidgetSize::parse_short(size_s), CanvasSlot::parse(slot_s))
            {
                return Ok(CanvasId::new(size, slot));
            }
        }
        // Also accept slot-first legacy confusion: one-sm
        if let Some((slot_s, size_s)) = raw.split_once('-') {
            if let (Some(slot), Some(size)) =
                (CanvasSlot::parse(slot_s), WidgetSize::parse_short(size_s))
            {
                return Ok(CanvasId::new(size, slot));
            }
        }
        // Helpful errors for old three-slot scheme
        if matches!(raw.as_str(), "one" | "two" | "three") {
            return Err(Error::UnknownCanvas(format!(
                "{raw} is obsolete; use size-first ids like sm-{raw}, md-{raw}, lg-{raw}, xl-{raw}"
            )));
        }
        Err(Error::UnknownCanvas(format!(
            "{s} (expected sm|md|lg|xl - one|two|three, e.g. sm-one)"
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
    fn parse_size_first() {
        let id = CanvasId::parse("sm-one").unwrap();
        assert_eq!(id.size, WidgetSize::Small);
        assert_eq!(id.slot, CanvasSlot::One);
        assert_eq!(id.as_str(), "sm-one");
        assert_eq!(id.widget_kind(), "AgentCanvas.sm-one");
    }

    #[test]
    fn all_twelve_unique() {
        let mut set = std::collections::HashSet::new();
        for id in CanvasId::ALL {
            assert!(set.insert(id.as_str()));
        }
        assert_eq!(set.len(), 12);
    }

    #[test]
    fn legacy_one_errors_helpfully() {
        let err = CanvasId::parse("one").unwrap_err().to_string();
        assert!(err.contains("sm-one") || err.contains("obsolete"));
    }
}
