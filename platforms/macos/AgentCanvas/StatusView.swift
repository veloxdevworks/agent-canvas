import SwiftUI
import AppKit
import WidgetKit

/// End-user host window: status, canvases, light actions — not the seed lab.
struct StatusView: View {
    @EnvironmentObject private var reloadWatcher: ReloadWatcher
    @Environment(\.openWindow) private var openWindow

    @State private var summaries: [AddressSummary] = []
    @State private var showOnboarding = false
    @State private var showHowTo = false
    @State private var showChecklist: Bool = !UserGuide.checklistDismissed
    @State private var selectedId: String?
    @State private var statusNote: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if showChecklist && !UserGuide.checklistDismissed {
                ChecklistBanner(
                    onOpenConnect: { openWindow(id: "connect-wizard") },
                    onOpenHowTo: { showHowTo = true },
                    onDismiss: {
                        UserGuide.checklistDismissed = true
                        showChecklist = false
                    }
                )
            }

            canvasList
            actions
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 520)
        .onAppear {
            reloadWatcher.start()
            refresh()
            if !UserGuide.hasCompletedOnboarding {
                showOnboarding = true
            }
            showChecklist = !UserGuide.checklistDismissed
        }
        // Local list refresh only — avoid publishing on ReloadWatcher every tick
        // (that was rebuilding the menu bar and dismissing Connect MCP mid-hover).
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            refreshLocalSummariesOnly()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentCanvasShowHowTo)) { _ in
            showHowTo = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentCanvasOpenConnect)) { note in
            if let client = note.object as? ConnectWizardClient {
                reloadWatcher.preferredConnectClient = client
            }
            openWindow(id: "connect-wizard")
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentCanvasOpenSeed)) { _ in
            openWindow(id: "seed")
        }
        .sheet(isPresented: $showOnboarding) {
            HowToUseView {
                showOnboarding = false
                showChecklist = !UserGuide.checklistDismissed
            }
        }
        .sheet(isPresented: $showHowTo) {
            HowToUseView(showsDismissActions: true) {
                showHowTo = false
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agent Canvas")
                    .font(.largeTitle.bold())
                Text("Desktop widgets your agent can write. Keep this app in the menu bar for live updates.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Label(
                    reloadWatcher.isWatching ? "Watching" : "Starting…",
                    systemImage: reloadWatcher.isWatching ? "antenna.radiowaves.left.and.right" : "ellipsis"
                )
                .font(.caption)
                .foregroundStyle(reloadWatcher.isWatching ? .green : .secondary)
                Text(reloadWatcher.canvasFillSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canvasList: some View {
        GroupBox("Canvases") {
            if summaries.allSatisfy({ !$0.hasContent }) {
                emptyState
                    .padding(.vertical, 12)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(CanvasSize.allCases, id: \.rawValue) { size in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(size.galleryLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(summaries.filter { $0.size == size }) { s in
                                canvasRow(s)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 320)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No canvas content yet")
                .font(.headline)
            Text(
                "Connect Cursor or Claude, then ask the agent to update a canvas. "
                    + "Or copy a ready-made prompt for Medium · One (md-one)."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            HStack {
                Button("Connect agent…") {
                    openWindow(id: "connect-wizard")
                }
                .buttonStyle(.borderedProminent)
                Button("Copy prompt for md-one") {
                    UserGuide.copyUpdatePrompt(for: "md-one")
                    statusNote = "Prompt for md-one copied"
                }
                Button("Copy example prompt") {
                    UserGuide.copyExamplePrompt()
                    statusNote = "Example prompt copied"
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func canvasRow(_ s: AddressSummary) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(s.hasContent ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
            Text(s.name)
                .fontWeight(.medium)
            Text(s.id)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
            Spacer()
            Text(s.detail)
                .foregroundStyle(.secondary)
                .font(.caption)
                .lineLimit(1)
            Menu {
                Button("Copy id \(s.id)") {
                    UserGuide.copyCanvasId(s.id)
                    statusNote = "Copied \(s.id)"
                }
                Button("Copy update prompt") {
                    UserGuide.copyUpdatePrompt(for: s.id)
                    statusNote = "Prompt for \(s.id) copied"
                }
                #if DEBUG
                if CloudFeature.isEnabled {
                    Divider()
                    Button("Cloud settings…") {
                        openWindow(id: "cloud")
                    }
                    if let share = CloudShareIndex.record(forCanvas: s.id) {
                        Button("Copy public URL") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(share.publicUrl, forType: .string)
                            statusNote = "Copied \(share.publicUrl)"
                        }
                    }
                }
                #endif
                Divider()
                Button("Clear this canvas", role: .destructive) {
                    if let address = CanvasAddress(rawValue: s.id) {
                        try? CanvasStorage.clear(address: address)
                        refresh()
                        statusNote = "Cleared \(s.id)"
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedId = s.id
        }
        .background(selectedId == s.id ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    private var actions: some View {
        HStack {
            Button("Reload widgets") {
                CanvasStorage.mirrorAllAndReload()
                reloadWatcher.noteManualReload()
                refresh()
                statusNote = "Widgets reloaded"
            }
            Button("Connect agent…") {
                openWindow(id: "connect-wizard")
            }
            Button("How to use…") {
                showHowTo = true
            }
            #if DEBUG
            if CloudFeature.isEnabled || CloudFeature.userToggleEnabled {
                Button("Cloud…") {
                    openWindow(id: "cloud")
                }
            }
            #endif
            Button("Clear all", role: .destructive) {
                try? CanvasStorage.clearAll()
                refresh()
                statusNote = "All canvases cleared"
            }
            Spacer()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(statusNote.isEmpty ? reloadWatcher.statusLine : statusNote)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Menu bar: Connect MCP · keep running for agent updates")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func refresh() {
        refreshLocalSummariesOnly()
        reloadWatcher.refreshCanvasCounts()
    }

    private func refreshLocalSummariesOnly() {
        summaries = CanvasAddress.allCases.map { address in
            let doc = CanvasStorage.load(address: address)
            let detail: String
            if doc.isEmptyContent {
                detail = "empty"
            } else if let t = doc.title, !t.isEmpty {
                detail = t
            } else {
                detail = "\(doc.sections.count) section(s)"
            }
            return AddressSummary(
                id: address.rawValue,
                name: address.displayName,
                size: address.size,
                hasContent: !doc.isEmptyContent,
                detail: detail
            )
        }
    }
}

struct AddressSummary: Identifiable {
    let id: String
    let name: String
    let size: CanvasSize
    let hasContent: Bool
    let detail: String
}
