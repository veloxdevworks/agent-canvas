import SwiftUI
import WidgetKit

/// Developer-only seed lab (not the default end-user window).
struct SeedDemosView: View {
    @EnvironmentObject private var reloadWatcher: ReloadWatcher
    @State private var summaries: [AddressSummary] = []

    @State private var seedSize: CanvasSize? = .md
    @State private var seedSlot: CanvasSlot? = nil
    @State private var seedKind: DemoKind = .bar

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Seed demos")
                    .font(.largeTitle.bold())
                Text("Developer tools — write sample content for testing widgets.")
                    .foregroundStyle(.secondary)
            }

            seedControls
            canvasList
            actions
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 560)
        .onAppear {
            reloadWatcher.start()
            refresh()
        }
    }

    private var seedControls: some View {
        GroupBox("Seed demos") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Size")
                        .frame(width: 56, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Picker("Size", selection: $seedSize) {
                        Text("All").tag(Optional<CanvasSize>.none)
                        ForEach(CanvasSize.allCases, id: \.rawValue) { size in
                            Text(size.galleryLabel).tag(Optional(size))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Slot")
                        .frame(width: 56, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Picker("Slot", selection: $seedSlot) {
                        Text("All").tag(Optional<CanvasSlot>.none)
                        ForEach(CanvasSlot.allCases, id: \.rawValue) { slot in
                            Text(slot.shortLabel).tag(Optional(slot))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                HStack(alignment: .top) {
                    Text("Content")
                        .frame(width: 56, alignment: .leading)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Content", selection: $seedKind) {
                            ForEach(DemoKind.allCases) { kind in
                                Text(kind.shortLabel).tag(kind)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 220, alignment: .leading)

                        FlowChips(selection: $seedKind, kinds: [
                            .metrics, .list, .bar, .line, .pie, .gauge, .full, .themed,
                        ])
                    }
                }

                HStack {
                    Text(seedTargetDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Seed") {
                        seedSelected()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var seedTargetDescription: String {
        let sizeLabel = seedSize?.galleryLabel ?? "all sizes"
        let slotLabel = seedSlot.map { "slot \($0.shortLabel)" } ?? "all slots"
        let count = DemoContent.addresses(size: seedSize, slot: seedSlot).count
        return "Write “\(seedKind.label)” → \(count) canvas(es) · \(sizeLabel) · \(slotLabel)"
    }

    private var canvasList: some View {
        GroupBox("Canvases") {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(CanvasSize.allCases, id: \.rawValue) { size in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(size.galleryLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(summaries.filter { $0.size == size }) { s in
                                HStack {
                                    Circle()
                                        .fill(s.hasContent ? Color.green : Color.secondary.opacity(0.4))
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
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 220)
        }
    }

    private var actions: some View {
        HStack {
            Button("Reload widgets") {
                CanvasStorage.mirrorAllAndReload()
                reloadWatcher.noteManualReload()
                refresh()
            }
            Button("Clear selected", role: .destructive) {
                clearSelected()
            }
            Button("Clear all", role: .destructive) {
                try? CanvasStorage.clearAll()
                refresh()
            }
            Spacer()
            Button("Open data folder") {
                CanvasStorage.ensureDirectories()
                NSWorkspace.shared.open(CanvasStorage.applicationSupportRoot)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reloadWatcher.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("CLI: just seed-demos md one bar   ·   just seed-demos lg all pie")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Text("Data: \(CanvasStorage.applicationSupportRoot.path)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }

    private func refresh() {
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

    private func seedSelected() {
        let targets = DemoContent.addresses(size: seedSize, slot: seedSlot)
        guard !targets.isEmpty else { return }
        for address in targets {
            let doc = DemoContent.document(for: address, kind: seedKind)
            try? CanvasStorage.write(doc, address: address, source: .seed)
            CanvasStorage.reload(address: address)
        }
        let ids = targets.map(\.rawValue).joined(separator: ", ")
        reloadWatcher.statusLine =
            "Seeded \(seedKind.shortLabel) → \(ids) at \(Date().formatted(date: .omitted, time: .standard))"
        refresh()
    }

    private func clearSelected() {
        let targets = DemoContent.addresses(size: seedSize, slot: seedSlot)
        for address in targets {
            try? CanvasStorage.clear(address: address)
        }
        reloadWatcher.statusLine = "Cleared \(targets.count) canvas(es)"
        refresh()
    }
}

private struct FlowChips: View {
    @Binding var selection: DemoKind
    let kinds: [DemoKind]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ForEach(kinds.prefix(4)) { kind in
                    chip(kind)
                }
            }
            HStack(spacing: 6) {
                ForEach(kinds.dropFirst(4)) { kind in
                    chip(kind)
                }
            }
        }
    }

    private func chip(_ kind: DemoKind) -> some View {
        Button(kind.shortLabel) {
            selection = kind
        }
        .buttonStyle(.bordered)
        .tint(selection == kind ? .accentColor : .secondary)
        .controlSize(.small)
    }
}
