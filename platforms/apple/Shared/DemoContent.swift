import Foundation

/// What to seed (aligned with Rust `DemoKind`).
enum DemoKind: String, CaseIterable, Identifiable {
    case themed
    case metrics
    case header
    case text
    case list
    case bar
    case line
    case pie
    case gauge
    case full

    var id: String { rawValue }

    var label: String {
        switch self {
        case .themed: return "Themed pack"
        case .metrics: return "Metrics"
        case .header: return "Header"
        case .text: return "Text"
        case .list: return "List"
        case .bar: return "Bar chart"
        case .line: return "Line chart"
        case .pie: return "Pie chart"
        case .gauge: return "Gauge"
        case .full: return "Full board"
        }
    }

    var shortLabel: String {
        switch self {
        case .themed: return "Themed"
        case .metrics: return "Metrics"
        case .header: return "Header"
        case .text: return "Text"
        case .list: return "List"
        case .bar: return "Bar"
        case .line: return "Line"
        case .pie: return "Pie"
        case .gauge: return "Gauge"
        case .full: return "Full"
        }
    }
}

/// Size-aware demo documents (keep recipes aligned with crates/agent-canvas-core/src/demos.rs).
enum DemoContent {
    static func document(for address: CanvasAddress, kind: DemoKind) -> CanvasDocument {
        var doc: CanvasDocument
        switch kind {
        case .themed:
            doc = themed(address)
        case .metrics:
            doc = metricsOnly(address)
        case .header:
            doc = headerOnly(address)
        case .text:
            doc = textOnly(address)
        case .list:
            doc = listOnly(address)
        case .bar:
            doc = chartOnly(address, type: .bar, title: "Bar demo")
        case .line:
            doc = chartOnly(address, type: .line, title: "Line demo")
        case .pie:
            doc = chartOnly(address, type: .pie, title: "Pie demo")
        case .gauge:
            doc = chartOnly(address, type: .gauge, title: "Gauge demo")
        case .full:
            doc = fullBoard(address)
        }
        if let t = doc.title, !t.contains(address.rawValue) {
            doc.title = "\(address.rawValue) · \(kind.shortLabel) · \(t)"
        } else if doc.title == nil {
            doc.title = "\(address.rawValue) · \(kind.shortLabel)"
        }
        return doc
    }

    static func addresses(size: CanvasSize?, slot: CanvasSlot?) -> [CanvasAddress] {
        CanvasAddress.allCases.filter { a in
            (size == nil || a.size == size) && (slot == nil || a.slot == slot)
        }
    }

    // MARK: - Explicit kinds

    private static func metricsOnly(_ address: CanvasAddress) -> CanvasDocument {
        var d = CanvasDocument.empty
        d.title = "Metrics"
        if address.size == .sm {
            d.sections = [
                .metrics(items: [
                    MetricItem(label: "A", value: "12", trend: "+2"),
                    MetricItem(label: "B", value: "4", trend: "-1"),
                ]),
            ]
        } else {
            d.sections = [
                .metrics(items: [
                    MetricItem(label: "Closed", value: "47", trend: "+12%"),
                    MetricItem(label: "Cycle", value: "2.3d", trend: "-0.4d"),
                    MetricItem(label: "WIP", value: "11", trend: "+1"),
                    MetricItem(label: "Bugs", value: "6", trend: "-2"),
                ]),
            ]
        }
        return d
    }

    private static func headerOnly(_ address: CanvasAddress) -> CanvasDocument {
        var d = CanvasDocument.empty
        d.sections = [
            .header(
                text: "\(address.size.galleryLabel) header",
                subtitle: "slot \(address.slot.shortLabel) · header-only seed"
            ),
        ]
        return d
    }

    private static func textOnly(_ address: CanvasAddress) -> CanvasDocument {
        var d = CanvasDocument.empty
        d.title = "Text"
        let body: String
        switch address.size {
        case .sm: body = "Short glance note."
        case .md: body = "Medium body copy for agent text sections. Soft-wraps across a couple of lines."
        default:
            body = "Longer body text for large canvases. Agents can drop status updates, runbook snippets, or incident context here without charts."
        }
        d.sections = [
            .header(text: "Notes", subtitle: address.rawValue),
            .text(content: body),
        ]
        return d
    }

    private static func listOnly(_ address: CanvasAddress) -> CanvasDocument {
        var d = CanvasDocument.empty
        d.title = "List"
        // Same real queue on every size — packing decides how many rows show.
        let items = [
            ListItem(primary: "API rate limiting", secondary: "ENG-4821", badge: "P1"),
            ListItem(primary: "Login SSO flake", secondary: "ENG-4902", badge: "P2"),
            ListItem(primary: "Search timeout", secondary: "ENG-4888", badge: "P2"),
            ListItem(primary: "Docs for MCP", secondary: "ENG-5010", badge: "P3"),
            ListItem(primary: "Flaky e2e", secondary: "ENG-4770", badge: "P3"),
            ListItem(primary: "Bump deps", secondary: "ENG-5101", badge: "LOW"),
        ]
        let listTitle: String? = address.size == .sm ? nil : "Queue"
        let subtitle: String? = address.size == .sm ? nil : "list seed"
        d.sections = [
            .header(text: "Open items", subtitle: subtitle),
            .list(title: listTitle, items: items),
        ]
        return d
    }

    private static func chartOnly(
        _ address: CanvasAddress,
        type: ChartType,
        title: String
    ) -> CanvasDocument {
        var d = CanvasDocument.empty
        d.title = title
        let data: [ChartPoint]
        switch type {
        case .gauge:
            data = [
                ChartPoint(label: "Budget", value: 78),
                ChartPoint(label: "Max", value: 100),
            ]
        case .pie:
            data = [
                ChartPoint(label: "API", value: 45),
                ChartPoint(label: "Web", value: 30),
                ChartPoint(label: "Mobile", value: 18),
                ChartPoint(label: "Jobs", value: 7),
            ]
        case .line:
            if address.size == .sm {
                data = [
                    ChartPoint(label: "M", value: 4),
                    ChartPoint(label: "T", value: 7),
                    ChartPoint(label: "W", value: 5),
                    ChartPoint(label: "T", value: 8),
                    ChartPoint(label: "F", value: 6),
                ]
            } else {
                data = [
                    ChartPoint(label: "00", value: 12),
                    ChartPoint(label: "04", value: 8),
                    ChartPoint(label: "08", value: 22),
                    ChartPoint(label: "12", value: 31),
                    ChartPoint(label: "16", value: 28),
                    ChartPoint(label: "20", value: 19),
                    ChartPoint(label: "24", value: 14),
                ]
            }
        case .bar:
            if address.size == .sm {
                data = [
                    ChartPoint(label: "M", value: 3),
                    ChartPoint(label: "T", value: 5),
                    ChartPoint(label: "W", value: 2),
                    ChartPoint(label: "T", value: 6),
                    ChartPoint(label: "F", value: 4),
                ]
            } else {
                data = [
                    ChartPoint(label: "Mon", value: 8),
                    ChartPoint(label: "Tue", value: 12),
                    ChartPoint(label: "Wed", value: 6),
                    ChartPoint(label: "Thu", value: 9),
                    ChartPoint(label: "Fri", value: 12),
                    ChartPoint(label: "Sat", value: 3),
                    ChartPoint(label: "Sun", value: 2),
                ]
            }
        }
        d.sections = [
            .header(text: title, subtitle: "\(type.rawValue) chart seed"),
            .chart(chartType: type, title: title, data: data),
        ]
        return d
    }

    private static func fullBoard(_ address: CanvasAddress) -> CanvasDocument {
        var d = CanvasDocument.empty
        d.title = "Full board"
        d.sections = [
            .header(
                text: "Full board",
                subtitle: "\(address.size.galleryLabel) · all primitives"
            ),
            .metrics(items: [
                MetricItem(label: "Closed", value: "47", trend: "+12%"),
                MetricItem(label: "Cycle", value: "2.3d", trend: "-0.4d"),
                MetricItem(label: "WIP", value: "11", trend: "+1"),
                MetricItem(label: "Bugs", value: "6", trend: "-2"),
            ]),
            .chart(chartType: .bar, title: "Daily", data: [
                ChartPoint(label: "M", value: 8),
                ChartPoint(label: "T", value: 12),
                ChartPoint(label: "W", value: 6),
                ChartPoint(label: "T", value: 9),
                ChartPoint(label: "F", value: 12),
            ]),
            .chart(chartType: .line, title: "Trend", data: [
                ChartPoint(label: "1", value: 10),
                ChartPoint(label: "2", value: 14),
                ChartPoint(label: "3", value: 11),
                ChartPoint(label: "4", value: 18),
                ChartPoint(label: "5", value: 16),
            ]),
            .list(title: "Queue", items: [
                ListItem(primary: "API rate limiting", secondary: "ENG-4821", badge: "P1"),
                ListItem(primary: "SSO flake", secondary: "ENG-4902", badge: "P2"),
                ListItem(primary: "Search timeout", secondary: "ENG-4888", badge: "P2"),
            ]),
            .text(content: "Full-board seed mixes metrics, charts, list, and text."),
        ]
        return d
    }

    // MARK: - Themed packs

    private static func themed(_ address: CanvasAddress) -> CanvasDocument {
        switch address.size {
        case .sm: return small(slot: address.slot)
        case .md: return medium(slot: address.slot)
        case .lg: return large(slot: address.slot)
        case .xl: return xl(slot: address.slot)
        }
    }

    private static func small(slot: CanvasSlot) -> CanvasDocument {
        var d = CanvasDocument.empty
        switch slot {
        case .one:
            d.title = "Build"
            d.sections = [
                .metrics(items: [
                    MetricItem(label: "CI", value: "✓", trend: "ok"),
                    MetricItem(label: "Queue", value: "2", trend: "-1"),
                ]),
            ]
        case .two:
            d.title = "Alerts"
            d.sections = [
                .metrics(items: [
                    MetricItem(label: "P1", value: "0", trend: "0"),
                    MetricItem(label: "P2", value: "3", trend: "+1"),
                ]),
            ]
        case .three:
            d.title = "Ship"
            d.sections = [
                .metrics(items: [
                    MetricItem(label: "Deploys", value: "1", trend: "today"),
                    MetricItem(label: "Canary", value: "ok", trend: nil),
                ]),
            ]
        }
        return d
    }

    private static func medium(slot: CanvasSlot) -> CanvasDocument {
        var d = CanvasDocument.empty
        switch slot {
        case .one:
            d.title = "Sprint pulse"
            d.sections = [
                .header(text: "Sprint 24", subtitle: "3 days left"),
                .metrics(items: [
                    MetricItem(label: "Done", value: "18", trend: "+4"),
                    MetricItem(label: "WIP", value: "7", trend: "-1"),
                    MetricItem(label: "Blocked", value: "2", trend: "+1"),
                ]),
                .list(title: "Focus", items: [
                    ListItem(primary: "Ship rate-limit fix", secondary: "ENG-4821", badge: "P1"),
                    ListItem(primary: "SSO flake", secondary: "ENG-4902", badge: "P2"),
                    ListItem(primary: "Docs for MCP", secondary: "ENG-5010", badge: "P3"),
                ]),
            ]
        case .two:
            d.title = "Traffic mix"
            d.sections = [
                .header(text: "Traffic mix", subtitle: "Share of requests"),
                .chart(chartType: .pie, title: "By surface", data: [
                    ChartPoint(label: "API", value: 45),
                    ChartPoint(label: "Web", value: 30),
                    ChartPoint(label: "Mobile", value: 18),
                    ChartPoint(label: "Jobs", value: 7),
                ]),
                .metrics(items: [
                    MetricItem(label: "RPS", value: "1.2k", trend: "+8%"),
                    MetricItem(label: "Cache", value: "91%", trend: "+2%"),
                ]),
            ]
        case .three:
            d.title = "Agent load"
            d.sections = [
                .header(text: "Agent sessions", subtitle: "Today"),
                .metrics(items: [
                    MetricItem(label: "Active", value: "6", trend: "+2"),
                    MetricItem(label: "Tokens", value: "1.1M", trend: "+12%"),
                    MetricItem(label: "Tools", value: "84", trend: "+9"),
                ]),
                .chart(chartType: .bar, title: "Calls / hour", data: [
                    ChartPoint(label: "9a", value: 12),
                    ChartPoint(label: "11a", value: 28),
                    ChartPoint(label: "1p", value: 22),
                    ChartPoint(label: "3p", value: 35),
                    ChartPoint(label: "5p", value: 18),
                ]),
            ]
        }
        return d
    }

    private static func large(slot: CanvasSlot) -> CanvasDocument {
        var d = CanvasDocument.empty
        switch slot {
        case .one:
            d.title = "Jira throughput"
            d.sections = [
                .header(text: "Jira throughput", subtitle: "Last 7 days"),
                .metrics(items: [
                    MetricItem(label: "Closed", value: "47", trend: "+12%"),
                    MetricItem(label: "Cycle", value: "2.3d", trend: "-0.4d"),
                    MetricItem(label: "WIP", value: "11", trend: "+1"),
                    MetricItem(label: "Bugs", value: "6", trend: "-2"),
                ]),
                .chart(chartType: .bar, title: "Daily closures", data: [
                    ChartPoint(label: "Mon", value: 8),
                    ChartPoint(label: "Tue", value: 12),
                    ChartPoint(label: "Wed", value: 6),
                    ChartPoint(label: "Thu", value: 9),
                    ChartPoint(label: "Fri", value: 12),
                    ChartPoint(label: "Sat", value: 3),
                    ChartPoint(label: "Sun", value: 2),
                ]),
                .list(title: "Open high priority", items: [
                    ListItem(primary: "API rate limiting", secondary: "ENG-4821", badge: "P1"),
                    ListItem(primary: "Login SSO flake", secondary: "ENG-4902", badge: "P2"),
                    ListItem(primary: "Search timeout", secondary: "ENG-4888", badge: "P2"),
                ]),
            ]
        case .two:
            d.title = "PR queue"
            d.sections = [
                .header(text: "Review queue", subtitle: "Engineering"),
                .metrics(items: [
                    MetricItem(label: "Open", value: "14", trend: "+3"),
                    MetricItem(label: "Stale >2d", value: "5", trend: "+1"),
                    MetricItem(label: "Avg age", value: "1.4d", trend: "-0.2d"),
                ]),
                .chart(chartType: .bar, title: "PRs opened / day", data: [
                    ChartPoint(label: "M", value: 4),
                    ChartPoint(label: "T", value: 7),
                    ChartPoint(label: "W", value: 5),
                    ChartPoint(label: "T", value: 9),
                    ChartPoint(label: "F", value: 6),
                ]),
                .list(title: "Needs review", items: [
                    ListItem(primary: "feat: size-first ids", secondary: "you · 2h", badge: "NEW"),
                    ListItem(primary: "fix: widget reload", secondary: "alex · 1d", badge: "REVIEW"),
                    ListItem(primary: "chore: bump deps", secondary: "bot · 3d", badge: "STALE"),
                ]),
            ]
        case .three:
            d.title = "Latency"
            d.sections = [
                .header(text: "API latency", subtitle: "p50 / p95"),
                .metrics(items: [
                    MetricItem(label: "p50", value: "42ms", trend: "-3ms"),
                    MetricItem(label: "p95", value: "180ms", trend: "+8ms"),
                    MetricItem(label: "p99", value: "410ms", trend: "+20ms"),
                ]),
                .chart(chartType: .line, title: "p95 over day", data: [
                    ChartPoint(label: "00", value: 120),
                    ChartPoint(label: "04", value: 95),
                    ChartPoint(label: "08", value: 160),
                    ChartPoint(label: "12", value: 210),
                    ChartPoint(label: "16", value: 190),
                    ChartPoint(label: "20", value: 150),
                ]),
                .text(content: "Spike at noon coincides with batch export job."),
            ]
        }
        return d
    }

    private static func xl(slot: CanvasSlot) -> CanvasDocument {
        var d = CanvasDocument.empty
        switch slot {
        case .one:
            d.title = "Platform health"
            d.sections = [
                .header(text: "Platform health", subtitle: "Prod · last 24h", icon: .server),
                .metrics(items: [
                    MetricItem(label: "Uptime", value: "99.97%", trend: "+0.01", icon: .check, tone: .success),
                    MetricItem(label: "p95 lat", value: "142ms", trend: "-12ms", icon: .clock),
                    MetricItem(label: "Errors", value: "0.12%", trend: "-0.03", icon: .alert, tone: .critical),
                    MetricItem(label: "Deploys", value: "4", trend: "+1", icon: .rocket),
                ]),
                .chart(chartType: .line, title: "Request rate (k/min)", data: [
                    ChartPoint(label: "00", value: 12),
                    ChartPoint(label: "04", value: 8),
                    ChartPoint(label: "08", value: 22),
                    ChartPoint(label: "12", value: 31),
                    ChartPoint(label: "16", value: 28),
                    ChartPoint(label: "20", value: 19),
                    ChartPoint(label: "24", value: 14),
                ]),
                .chart(chartType: .gauge, title: "Error budget remaining", data: [
                    ChartPoint(label: "Budget", value: 78),
                    ChartPoint(label: "Max", value: 100),
                ]),
                .list(title: "Active incidents", items: [
                    ListItem(primary: "Elevated 5xx on payments", secondary: "INC-204", badge: "P1", icon: .alert, tone: .critical),
                    ListItem(primary: "CDN cache miss spike", secondary: "INC-201", badge: "P2", icon: .warning, tone: .warning),
                ]),
                .icon(name: .check, tone: .success, size: .md, priority: nil),
                .text(content: "On-call: Alex · Secondary: Jordan."),
            ]
        case .two:
            d.title = "Cost & usage"
            d.sections = [
                .header(text: "Cloud spend", subtitle: "MTD vs forecast"),
                .metrics(items: [
                    MetricItem(label: "MTD", value: "$48k", trend: "+6%"),
                    MetricItem(label: "Forecast", value: "$71k", trend: "on track"),
                    MetricItem(label: "GPU", value: "$12k", trend: "+18%"),
                    MetricItem(label: "Idle", value: "9%", trend: "-2%"),
                ]),
                .chart(chartType: .bar, title: "Daily $", data: [
                    ChartPoint(label: "1", value: 2.1),
                    ChartPoint(label: "5", value: 2.4),
                    ChartPoint(label: "10", value: 2.8),
                    ChartPoint(label: "15", value: 2.6),
                    ChartPoint(label: "20", value: 3.1),
                    ChartPoint(label: "25", value: 2.9),
                ]),
                .chart(chartType: .pie, title: "By service", data: [
                    ChartPoint(label: "Compute", value: 40),
                    ChartPoint(label: "Storage", value: 22),
                    ChartPoint(label: "GPU", value: 25),
                    ChartPoint(label: "Net", value: 13),
                ]),
                .list(title: "Top cost drivers", items: [
                    ListItem(primary: "training-job-7", secondary: "GPU · $4.2k", badge: "HOT"),
                    ListItem(primary: "logs-hot-tier", secondary: "Storage · $1.1k", badge: "WATCH"),
                ]),
            ]
        case .three:
            d.title = "Release train"
            d.sections = [
                .header(text: "Release train", subtitle: "v2.8.0"),
                .metrics(items: [
                    MetricItem(label: "RC", value: "rc.3", trend: nil),
                    MetricItem(label: "Tests", value: "99.1%", trend: "+0.2"),
                    MetricItem(label: "Blockers", value: "1", trend: "-2"),
                    MetricItem(label: "ETA", value: "Thu", trend: nil),
                ]),
                .chart(chartType: .line, title: "Flake rate %", data: [
                    ChartPoint(label: "W1", value: 2.1),
                    ChartPoint(label: "W2", value: 1.8),
                    ChartPoint(label: "W3", value: 1.4),
                    ChartPoint(label: "W4", value: 1.1),
                ]),
                .list(title: "Checklist", items: [
                    ListItem(primary: "Migration dry-run", secondary: "done", badge: "OK"),
                    ListItem(primary: "Security review", secondary: "pending", badge: "P2"),
                    ListItem(primary: "Comms draft", secondary: "in review", badge: "P3"),
                ]),
                .text(content: "Ship window: Thu 14:00 PT · rollback plan linked in runbook."),
            ]
        }
        return d
    }
}
