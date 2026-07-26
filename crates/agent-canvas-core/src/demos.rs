//! Demo documents for thorough widget testing.
//! Choose **what** to seed (`DemoKind`) and **where** (size × slot).

use crate::id::{CanvasId, CanvasSlot};
use crate::layout::WidgetSize;
use crate::schema::{Action, CanvasDocument, ChartPoint, ChartType, ListItem, MetricItem, Section};

/// What content recipe to write onto the selected canvas(es).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DemoKind {
    /// Size+slot themed pack (previous default behaviour).
    Themed,
    /// Metrics only.
    Metrics,
    /// Header + subtitle.
    Header,
    /// Body text.
    Text,
    /// List with badges.
    List,
    /// Bar chart (+ small header).
    Bar,
    /// Line chart.
    Line,
    /// Pie chart.
    Pie,
    /// Gauge / meter.
    Gauge,
    /// Dense multi-section board (clipped by widget size).
    Full,
}

impl DemoKind {
    pub const ALL: [DemoKind; 10] = [
        DemoKind::Themed,
        DemoKind::Metrics,
        DemoKind::Header,
        DemoKind::Text,
        DemoKind::List,
        DemoKind::Bar,
        DemoKind::Line,
        DemoKind::Pie,
        DemoKind::Gauge,
        DemoKind::Full,
    ];

    pub fn as_str(self) -> &'static str {
        match self {
            DemoKind::Themed => "themed",
            DemoKind::Metrics => "metrics",
            DemoKind::Header => "header",
            DemoKind::Text => "text",
            DemoKind::List => "list",
            DemoKind::Bar => "bar",
            DemoKind::Line => "line",
            DemoKind::Pie => "pie",
            DemoKind::Gauge => "gauge",
            DemoKind::Full => "full",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            DemoKind::Themed => "Themed pack",
            DemoKind::Metrics => "Metrics",
            DemoKind::Header => "Header",
            DemoKind::Text => "Text",
            DemoKind::List => "List",
            DemoKind::Bar => "Bar chart",
            DemoKind::Line => "Line chart",
            DemoKind::Pie => "Pie chart",
            DemoKind::Gauge => "Gauge",
            DemoKind::Full => "Full board",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "themed" | "theme" | "auto" | "default" => Some(DemoKind::Themed),
            "metrics" | "metric" | "numbers" => Some(DemoKind::Metrics),
            "header" | "title" => Some(DemoKind::Header),
            "text" | "body" => Some(DemoKind::Text),
            "list" | "lists" => Some(DemoKind::List),
            "bar" | "bars" | "barchart" => Some(DemoKind::Bar),
            "line" | "spark" => Some(DemoKind::Line),
            "pie" | "donut" => Some(DemoKind::Pie),
            "gauge" | "meter" | "progress" => Some(DemoKind::Gauge),
            "full" | "all" | "rich" | "dashboard" => Some(DemoKind::Full),
            _ => None,
        }
    }
}

/// Build a demo document for a canvas + content kind.
pub fn demo_document(id: CanvasId) -> CanvasDocument {
    demo_document_kind(id, DemoKind::Themed)
}

pub fn demo_document_kind(id: CanvasId, kind: DemoKind) -> CanvasDocument {
    let mut doc = match kind {
        DemoKind::Themed => themed(id),
        DemoKind::Metrics => metrics_only(id),
        DemoKind::Header => header_only(id),
        DemoKind::Text => text_only(id),
        DemoKind::List => list_only(id),
        DemoKind::Bar => chart_only(id, ChartType::Bar, "Bar demo"),
        DemoKind::Line => chart_only(id, ChartType::Line, "Line demo"),
        DemoKind::Pie => chart_only(id, ChartType::Pie, "Pie demo"),
        DemoKind::Gauge => chart_only(id, ChartType::Gauge, "Gauge demo"),
        DemoKind::Full => full_board(id),
    };
    stamp_id(&mut doc, id, kind);
    doc
}

/// All canvas ids matching optional size/slot filters (`None` = all).
pub fn matching_ids(size: Option<WidgetSize>, slot: Option<CanvasSlot>) -> Vec<CanvasId> {
    CanvasId::ALL
        .into_iter()
        .filter(|id| size.map(|s| id.size == s).unwrap_or(true))
        .filter(|id| slot.map(|s| id.slot == s).unwrap_or(true))
        .collect()
}

fn stamp_id(doc: &mut CanvasDocument, id: CanvasId, kind: DemoKind) {
    let tag = format!("{} · {}", id.as_str(), kind.label());
    match &doc.title {
        None => doc.title = Some(tag),
        Some(t) if t.contains(id.as_str()) => {}
        Some(t) => doc.title = Some(format!("{tag} · {t}")),
    }
}

// ── Kind builders ───────────────────────────────────────────────────────────

fn metrics_only(id: CanvasId) -> CanvasDocument {
    CanvasDocument {
        version: 1,
        updated_at: chrono::Utc::now(),
        cover: None,
        on_open: None,
        detail: None,
        title: Some("Metrics".into()),
        sections: vec![Section::Metrics {
            items: match id.size {
                WidgetSize::Small => vec![m("A", "12", Some("+2")), m("B", "4", Some("-1"))],
                _ => vec![
                    m("Closed", "47", Some("+12%")),
                    m("Cycle", "2.3d", Some("-0.4d")),
                    m("WIP", "11", Some("+1")),
                    m("Bugs", "6", Some("-2")),
                ],
            },
            priority: None,
        }],
    }
}

fn header_only(id: CanvasId) -> CanvasDocument {
    CanvasDocument {
        version: 1,
        updated_at: chrono::Utc::now(),
        cover: None,
        on_open: None,
        detail: None,
        title: None,
        sections: vec![Section::Header {
            text: format!("{} header", id.size.display_label()),
            subtitle: Some(format!("slot {} · header-only seed", id.slot.as_str())),
            tone: None,
            emphasis: None,
            priority: None,
        }],
    }
}

fn text_only(id: CanvasId) -> CanvasDocument {
    CanvasDocument {
        version: 1,
        updated_at: chrono::Utc::now(),
        cover: None,
        on_open: None,
        detail: None,
        title: Some("Text".into()),
        sections: vec![
            Section::Header {
                text: "Notes".into(),
                subtitle: Some(id.as_str().into()),
             tone: None,
             emphasis: None,
             priority: None, },
            Section::Text {
                content: match id.size {
                    WidgetSize::Small => "Short glance note.".into(),
                    WidgetSize::Medium => {
                        "Medium body copy for agent text sections. Soft-wraps across a couple of lines."
                            .into()
                    }
                    _ => "Longer body text for large canvases. Agents can drop status updates, runbook \
                         snippets, or incident context here without charts."
                        .into(),
                },
                tone: None,
                emphasis: None,
                priority: None,
            },
        ],
    }
}

fn list_only(id: CanvasId) -> CanvasDocument {
    // Same real queue on every size so sm/md show actual issues, not "Top item" stubs.
    // Row-fit packing decides how many are visible; footer reports "+N more in list".
    let items = vec![
        li_action("API rate limiting", "ENG-4821", "P1", Action::Url { url: "https://example.com/ENG-4821".into() }),
        li("Login SSO flake", "ENG-4902", "P2"),
        li("Search timeout", "ENG-4888", "P2"),
        li("Docs for MCP", "ENG-5010", "P3"),
        li("Flaky e2e", "ENG-4770", "P3"),
        li("Bump deps", "ENG-5101", "LOW"),
    ];
    // sm: no list section title — every point of height is a row.
    let list_title = match id.size {
        WidgetSize::Small => None,
        _ => Some("Queue".into()),
    };
    CanvasDocument {
        version: 1,
        updated_at: chrono::Utc::now(),
        cover: None,
        on_open: Some(Action::Expand),
        detail: Some(crate::schema::CanvasDetail {
            sections: vec![
                Section::Header {
                    text: "Open items".into(),
                    subtitle: Some("Expanded queue".into()),
                    tone: None,
                    emphasis: None,
                    priority: None,
                },
                Section::Text {
                    content: "Row actions open in the browser. Small widgets use whole-tile expand only."
                        .into(),
                    tone: None,
                    emphasis: None,
                    priority: None,
                },
                Section::List {
                    title: Some("Queue".into()),
                    items: items.clone(),
                    priority: None,
                },
            ],
        }),
        title: Some("List".into()),
        sections: vec![
            Section::Header {
                text: "Open items".into(),
                subtitle: match id.size {
                    WidgetSize::Small => None,
                    _ => Some("Tap a row on md+".into()),
                },
                tone: None,
                emphasis: None,
                priority: None,
            },
            Section::List {
                title: list_title,
                items,
                priority: None,
            },
        ],
    }
}

fn chart_only(id: CanvasId, chart_type: ChartType, title: &str) -> CanvasDocument {
    let data = match chart_type {
        ChartType::Gauge => vec![p("Budget", 78.0), p("Max", 100.0)],
        ChartType::Pie => vec![
            p("API", 45.0),
            p("Web", 30.0),
            p("Mobile", 18.0),
            p("Jobs", 7.0),
        ],
        ChartType::Line => match id.size {
            WidgetSize::Small => vec![
                p("M", 4.0),
                p("T", 7.0),
                p("W", 5.0),
                p("T", 8.0),
                p("F", 6.0),
            ],
            _ => vec![
                p("00", 12.0),
                p("04", 8.0),
                p("08", 22.0),
                p("12", 31.0),
                p("16", 28.0),
                p("20", 19.0),
                p("24", 14.0),
            ],
        },
        ChartType::Bar => match id.size {
            WidgetSize::Small => vec![
                p("M", 3.0),
                p("T", 5.0),
                p("W", 2.0),
                p("T", 6.0),
                p("F", 4.0),
            ],
            _ => vec![
                p("Mon", 8.0),
                p("Tue", 12.0),
                p("Wed", 6.0),
                p("Thu", 9.0),
                p("Fri", 12.0),
                p("Sat", 3.0),
                p("Sun", 2.0),
            ],
        },
    };
    CanvasDocument {
        version: 1,
        updated_at: chrono::Utc::now(),
        cover: None,
        on_open: None,
        detail: None,
        title: Some(title.into()),
        sections: vec![
            Section::Header {
                text: title.into(),
                subtitle: Some(format!("{} chart seed", chart_type_label(chart_type))),
                tone: None,
                emphasis: None,
                priority: None,
            },
            Section::Chart {
                chart_type,
                title: Some(title.into()),
                data,
                priority: None,
            },
        ],
    }
}

fn full_board(id: CanvasId) -> CanvasDocument {
    // Dense content; widget renderer clips by size.sectionCap.
    CanvasDocument {
        version: 1,
        updated_at: chrono::Utc::now(),
        cover: None,
        on_open: None,
        detail: None,
        title: Some("Full board".into()),
        sections: vec![
            Section::Header {
                text: "Full board".into(),
                subtitle: Some(format!("{} · all primitives", id.size.display_label())),
                tone: None,
                emphasis: None,
                priority: None,
            },
            Section::Metrics {
                items: vec![
                    m("Closed", "47", Some("+12%")),
                    m("Cycle", "2.3d", Some("-0.4d")),
                    m("WIP", "11", Some("+1")),
                    m("Bugs", "6", Some("-2")),
                ],
                priority: None,
            },
            Section::Chart {
                chart_type: ChartType::Bar,
                title: Some("Daily".into()),
                data: vec![
                    p("M", 8.0),
                    p("T", 12.0),
                    p("W", 6.0),
                    p("T", 9.0),
                    p("F", 12.0),
                ],
                priority: None,
            },
            Section::Chart {
                chart_type: ChartType::Line,
                title: Some("Trend".into()),
                data: vec![
                    p("1", 10.0),
                    p("2", 14.0),
                    p("3", 11.0),
                    p("4", 18.0),
                    p("5", 16.0),
                ],
                priority: None,
            },
            Section::List {
                title: Some("Queue".into()),
                items: vec![
                    li("API rate limiting", "ENG-4821", "P1"),
                    li("SSO flake", "ENG-4902", "P2"),
                    li("Search timeout", "ENG-4888", "P2"),
                ],
                priority: None,
            },
            Section::Text {
                content: "Full-board seed mixes metrics, charts, list, and text.".into(),
                tone: None,
                emphasis: None,
                priority: None,
            },
        ],
    }
}

fn chart_type_label(t: ChartType) -> &'static str {
    match t {
        ChartType::Bar => "bar",
        ChartType::Line => "line",
        ChartType::Pie => "pie",
        ChartType::Gauge => "gauge",
    }
}

// ── Themed packs (size × slot) ──────────────────────────────────────────────

fn themed(id: CanvasId) -> CanvasDocument {
    match id.size {
        WidgetSize::Small => demo_small(id.slot),
        WidgetSize::Medium => demo_medium(id.slot),
        WidgetSize::Large => demo_large(id.slot),
        WidgetSize::ExtraLarge => demo_xl(id.slot),
    }
}

fn demo_small(slot: CanvasSlot) -> CanvasDocument {
    let (title, metrics) = match slot {
        CanvasSlot::One => (
            "Build",
            vec![m("CI", "✓", Some("ok")), m("Queue", "2", Some("-1"))],
        ),
        CanvasSlot::Two => (
            "Alerts",
            vec![m("P1", "0", Some("0")), m("P2", "3", Some("+1"))],
        ),
        CanvasSlot::Three => (
            "Ship",
            vec![m("Deploys", "1", Some("today")), m("Canary", "ok", None)],
        ),
    };
    CanvasDocument {
        version: 1,
        updated_at: chrono::Utc::now(),
        cover: None,
        on_open: None,
        detail: None,
        title: Some(title.into()),
        sections: vec![Section::Metrics {
            items: metrics,
            priority: None,
        }],
    }
}

fn demo_medium(slot: CanvasSlot) -> CanvasDocument {
    match slot {
        CanvasSlot::One => CanvasDocument {
            version: 1,
            updated_at: chrono::Utc::now(),
            cover: None,
        on_open: None,
        detail: None,
            title: Some("Sprint pulse".into()),
            sections: vec![
                Section::Header {
                    text: "Sprint 24".into(),
                    subtitle: Some("3 days left".into()),
                    tone: None,
                    emphasis: None,
                    priority: None,
                },
                Section::Metrics {
                    items: vec![
                        m("Done", "18", Some("+4")),
                        m("WIP", "7", Some("-1")),
                        m("Blocked", "2", Some("+1")),
                    ],
                    priority: None,
                },
                Section::List {
                    title: Some("Focus".into()),
                    items: vec![
                        li("Ship rate-limit fix", "ENG-4821", "P1"),
                        li("SSO flake", "ENG-4902", "P2"),
                        li("Docs for MCP", "ENG-5010", "P3"),
                    ],
                    priority: None,
                },
            ],
        },
        CanvasSlot::Two => CanvasDocument {
            version: 1,
            updated_at: chrono::Utc::now(),
            cover: None,
        on_open: None,
        detail: None,
            title: Some("Traffic mix".into()),
            sections: vec![
                Section::Header {
                    text: "Traffic mix".into(),
                    subtitle: Some("Share of requests".into()),
                    tone: None,
                    emphasis: None,
                    priority: None,
                },
                Section::Chart {
                    chart_type: ChartType::Pie,
                    title: Some("By surface".into()),
                    data: vec![
                        p("API", 45.0),
                        p("Web", 30.0),
                        p("Mobile", 18.0),
                        p("Jobs", 7.0),
                    ],
                    priority: None,
                },
                Section::Metrics {
                    items: vec![
                        m("RPS", "1.2k", Some("+8%")),
                        m("Cache", "91%", Some("+2%")),
                    ],
                    priority: None,
                },
            ],
        },
        CanvasSlot::Three => CanvasDocument {
            version: 1,
            updated_at: chrono::Utc::now(),
            cover: None,
        on_open: None,
        detail: None,
            title: Some("Agent load".into()),
            sections: vec![
                Section::Header {
                    text: "Agent sessions".into(),
                    subtitle: Some("Today".into()),
                    tone: None,
                    emphasis: None,
                    priority: None,
                },
                Section::Metrics {
                    items: vec![
                        m("Active", "6", Some("+2")),
                        m("Tokens", "1.1M", Some("+12%")),
                        m("Tools", "84", Some("+9")),
                    ],
                    priority: None,
                },
                Section::Chart {
                    chart_type: ChartType::Bar,
                    title: Some("Calls / hour".into()),
                    data: vec![
                        p("9a", 12.0),
                        p("11a", 28.0),
                        p("1p", 22.0),
                        p("3p", 35.0),
                        p("5p", 18.0),
                    ],
                    priority: None,
                },
            ],
        },
    }
}

fn demo_large(slot: CanvasSlot) -> CanvasDocument {
    match slot {
        CanvasSlot::One => CanvasDocument {
            version: 1,
            updated_at: chrono::Utc::now(),
            cover: None,
        on_open: None,
        detail: None,
            title: Some("Jira throughput".into()),
            sections: vec![
                Section::Header {
                    text: "Jira throughput".into(),
                    subtitle: Some("Last 7 days".into()),
                    tone: None,
                    emphasis: None,
                    priority: None,
                },
                Section::Metrics {
                    items: vec![
                        m("Closed", "47", Some("+12%")),
                        m("Cycle", "2.3d", Some("-0.4d")),
                        m("WIP", "11", Some("+1")),
                        m("Bugs", "6", Some("-2")),
                    ],
                    priority: None,
                },
                Section::Chart {
                    chart_type: ChartType::Bar,
                    title: Some("Daily closures".into()),
                    data: vec![
                        p("Mon", 8.0),
                        p("Tue", 12.0),
                        p("Wed", 6.0),
                        p("Thu", 9.0),
                        p("Fri", 12.0),
                        p("Sat", 3.0),
                        p("Sun", 2.0),
                    ],
                    priority: None,
                },
                Section::List {
                    title: Some("Open high priority".into()),
                    items: vec![
                        li("API rate limiting", "ENG-4821", "P1"),
                        li("Login SSO flake", "ENG-4902", "P2"),
                        li("Search timeout", "ENG-4888", "P2"),
                    ],
                    priority: None,
                },
            ],
        },
        CanvasSlot::Two => CanvasDocument {
            version: 1,
            updated_at: chrono::Utc::now(),
            cover: None,
        on_open: None,
        detail: None,
            title: Some("PR queue".into()),
            sections: vec![
                Section::Header {
                    text: "Review queue".into(),
                    subtitle: Some("Engineering".into()),
                    tone: None,
                    emphasis: None,
                    priority: None,
                },
                Section::Metrics {
                    items: vec![
                        m("Open", "14", Some("+3")),
                        m("Stale >2d", "5", Some("+1")),
                        m("Avg age", "1.4d", Some("-0.2d")),
                    ],
                    priority: None,
                },
                Section::Chart {
                    chart_type: ChartType::Bar,
                    title: Some("PRs opened / day".into()),
                    data: vec![
                        p("M", 4.0),
                        p("T", 7.0),
                        p("W", 5.0),
                        p("T", 9.0),
                        p("F", 6.0),
                    ],
                    priority: None,
                },
                Section::List {
                    title: Some("Needs review".into()),
                    items: vec![
                        li("feat: size-first ids", "you · 2h", "NEW"),
                        li("fix: widget reload", "alex · 1d", "REVIEW"),
                        li("chore: bump deps", "bot · 3d", "STALE"),
                    ],
                    priority: None,
                },
            ],
        },
        CanvasSlot::Three => CanvasDocument {
            version: 1,
            updated_at: chrono::Utc::now(),
            cover: None,
        on_open: None,
        detail: None,
            title: Some("Latency".into()),
            sections: vec![
                Section::Header {
                    text: "API latency".into(),
                    subtitle: Some("p50 / p95".into()),
                    tone: None,
                    emphasis: None,
                    priority: None,
                },
                Section::Metrics {
                    items: vec![
                        m("p50", "42ms", Some("-3ms")),
                        m("p95", "180ms", Some("+8ms")),
                        m("p99", "410ms", Some("+20ms")),
                    ],
                    priority: None,
                },
                Section::Chart {
                    chart_type: ChartType::Line,
                    title: Some("p95 over day".into()),
                    data: vec![
                        p("00", 120.0),
                        p("04", 95.0),
                        p("08", 160.0),
                        p("12", 210.0),
                        p("16", 190.0),
                        p("20", 150.0),
                    ],
                    priority: None,
                },
                Section::Text {
                    content: "Spike at noon coincides with batch export job.".into(),
                    tone: None,
                    emphasis: None,
                    priority: None,
                },
            ],
        },
    }
}

fn demo_xl(slot: CanvasSlot) -> CanvasDocument {
    match slot {
        CanvasSlot::One => CanvasDocument {
            version: 1,
            updated_at: chrono::Utc::now(),
            cover: None,
        on_open: None,
        detail: None,
            title: Some("Platform health".into()),
            sections: vec![
                Section::Header {
                    text: "Platform health".into(),
                    subtitle: Some("Prod · last 24h".into()),
                    tone: None,
                    emphasis: None,
                    priority: None,
                },
                Section::Metrics {
                    items: vec![
                        m("Uptime", "99.97%", Some("+0.01")),
                        m("p95 lat", "142ms", Some("-12ms")),
                        m("Errors", "0.12%", Some("-0.03")),
                        m("Deploys", "4", Some("+1")),
                    ],
                    priority: None,
                },
                Section::Chart {
                    chart_type: ChartType::Line,
                    title: Some("Request rate (k/min)".into()),
                    data: vec![
                        p("00", 12.0),
                        p("04", 8.0),
                        p("08", 22.0),
                        p("12", 31.0),
                        p("16", 28.0),
                        p("20", 19.0),
                        p("24", 14.0),
                    ],
                    priority: None,
                },
                Section::Chart {
                    chart_type: ChartType::Gauge,
                    title: Some("Error budget remaining".into()),
                    data: vec![p("Budget", 78.0), p("Max", 100.0)],
                    priority: None,
                },
                Section::List {
                    title: Some("Active incidents".into()),
                    items: vec![
                        li("Elevated 5xx on payments", "INC-204", "P1"),
                        li("CDN cache miss spike", "INC-201", "P2"),
                    ],
                    priority: None,
                },
                Section::Text {
                    content: "On-call: Alex · Secondary: Jordan.".into(),
                    tone: None,
                    emphasis: None,
                    priority: None,
                },
            ],
        },
        CanvasSlot::Two => CanvasDocument {
            version: 1,
            updated_at: chrono::Utc::now(),
            cover: None,
        on_open: None,
        detail: None,
            title: Some("Cost & usage".into()),
            sections: vec![
                Section::Header {
                    text: "Cloud spend".into(),
                    subtitle: Some("MTD vs forecast".into()),
                    tone: None,
                    emphasis: None,
                    priority: None,
                },
                Section::Metrics {
                    items: vec![
                        m("MTD", "$48k", Some("+6%")),
                        m("Forecast", "$71k", Some("on track")),
                        m("GPU", "$12k", Some("+18%")),
                        m("Idle", "9%", Some("-2%")),
                    ],
                    priority: None,
                },
                Section::Chart {
                    chart_type: ChartType::Bar,
                    title: Some("Daily $".into()),
                    data: vec![
                        p("1", 2.1),
                        p("5", 2.4),
                        p("10", 2.8),
                        p("15", 2.6),
                        p("20", 3.1),
                        p("25", 2.9),
                    ],
                    priority: None,
                },
                Section::Chart {
                    chart_type: ChartType::Pie,
                    title: Some("By service".into()),
                    data: vec![
                        p("Compute", 40.0),
                        p("Storage", 22.0),
                        p("GPU", 25.0),
                        p("Net", 13.0),
                    ],
                    priority: None,
                },
                Section::List {
                    title: Some("Top cost drivers".into()),
                    items: vec![
                        li("training-job-7", "GPU · $4.2k", "HOT"),
                        li("logs-hot-tier", "Storage · $1.1k", "WATCH"),
                    ],
                    priority: None,
                },
            ],
        },
        CanvasSlot::Three => CanvasDocument {
            version: 1,
            updated_at: chrono::Utc::now(),
            cover: None,
        on_open: None,
        detail: None,
            title: Some("Release train".into()),
            sections: vec![
                Section::Header {
                    text: "Release train".into(),
                    subtitle: Some("v2.8.0".into()),
                    tone: None,
                    emphasis: None,
                    priority: None,
                },
                Section::Metrics {
                    items: vec![
                        m("RC", "rc.3", None),
                        m("Tests", "99.1%", Some("+0.2")),
                        m("Blockers", "1", Some("-2")),
                        m("ETA", "Thu", None),
                    ],
                    priority: None,
                },
                Section::Chart {
                    chart_type: ChartType::Line,
                    title: Some("Flake rate %".into()),
                    data: vec![p("W1", 2.1), p("W2", 1.8), p("W3", 1.4), p("W4", 1.1)],
                    priority: None,
                },
                Section::List {
                    title: Some("Checklist".into()),
                    items: vec![
                        li("Migration dry-run", "done", "OK"),
                        li("Security review", "pending", "P2"),
                        li("Comms draft", "in review", "P3"),
                    ],
                    priority: None,
                },
                Section::Text {
                    content: "Ship window: Thu 14:00 PT · rollback plan linked in runbook.".into(),
                    tone: None,
                    emphasis: None,
                    priority: None,
                },
            ],
        },
    }
}

fn m(label: &str, value: &str, trend: Option<&str>) -> MetricItem {
    MetricItem {
        label: label.into(),
        value: value.into(),
        trend: trend.map(str::to_string),
        tone: None,
        emphasis: None,
    }
}

fn li(primary: &str, secondary: &str, badge: &str) -> ListItem {
    ListItem {
        primary: primary.into(),
        secondary: Some(secondary.into()),
        badge: Some(badge.into()),
        action: None,
        tone: None,
        emphasis: None,
    }
}

fn li_action(primary: &str, secondary: &str, badge: &str, action: Action) -> ListItem {
    ListItem {
        primary: primary.into(),
        secondary: Some(secondary.into()),
        badge: Some(badge.into()),
        action: Some(action),
        tone: None,
        emphasis: None,
    }
}

fn p(label: &str, value: f64) -> ChartPoint {
    ChartPoint {
        label: label.into(),
        value,
    }
}
