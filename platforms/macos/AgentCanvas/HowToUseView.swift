import SwiftUI

/// First-run checklist and reusable “How to use” content.
struct HowToUseView: View {
    var showsDismissActions: Bool = true
    var onFinished: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("How to use Agent Canvas")
                    .font(.title2.bold())
                Text("Widgets on your desktop, written by your agent. Three steps:")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(UserGuide.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.accentColor))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title)
                                .font(.headline)
                            Text(step.body)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center) {
                        Text("Example prompt")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        Button {
                            UserGuide.copyExamplePrompt()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(CopyIconButtonStyle())
                        .help("Copy example prompt")
                    }

                    Text(UserGuide.examplePrompt)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(4)
            }

            if showsDismissActions {
                HStack {
                    Button("Show again later") {
                        UserGuide.checklistDismissed = true
                        // Don’t mark fully completed — can show again from menu.
                        onFinished?()
                    }
                    Spacer()
                    Button("Got it") {
                        UserGuide.hasCompletedOnboarding = true
                        UserGuide.checklistDismissed = true
                        onFinished?()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 480)
    }
}

/// Compact copy-control chrome: hover highlight + pressed state.
private struct CopyIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CopyIconButtonBody(configuration: configuration)
    }
}

private struct CopyIconButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(hovering || configuration.isPressed ? Color.primary : Color.secondary)
            .frame(width: 28, height: 28)
            .background(
                background,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }

    private var background: Color {
        if configuration.isPressed {
            return Color.primary.opacity(0.16)
        }
        if hovering {
            return Color.primary.opacity(0.1)
        }
        return .clear
    }
}

/// Compact checklist for the status window (dismissible).
struct ChecklistBanner: View {
    var onOpenConnect: () -> Void
    var onOpenHowTo: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Get started")
                        .font(.headline)
                    Spacer()
                    Button("Dismiss", action: onDismiss)
                        .buttonStyle(.borderless)
                }
                ForEach(Array(UserGuide.steps.enumerated()), id: \.offset) { i, step in
                    Label {
                        Text("\(step.title) — \(step.body)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Text("\(i + 1).")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Connect agent…", action: onOpenConnect)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("How to use…", action: onOpenHowTo)
                        .controlSize(.small)
                    Button("Copy example prompt") {
                        UserGuide.copyExamplePrompt()
                    }
                    .controlSize(.small)
                }
            }
            .padding(4)
        }
    }
}
