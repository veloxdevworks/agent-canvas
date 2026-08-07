import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var oauth: VeloxOAuthSession
    @EnvironmentObject private var sync: SubscriptionSync

    @State private var apiBase: String = CloudConfigStore.load().apiBaseURL
    @State private var pollSeconds: Int = CloudConfigStore.load().defaultPollIntervalSeconds
    @State private var issuerOverride: String = CloudConfigStore.load().oauthIssuerOverride ?? ""
    @State private var saveNote: String?

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Signed in as") {
                    Text(oauth.accountLabel ?? "—")
                }
                if let last = sync.lastSyncAt {
                    LabeledContent("Last sync") {
                        Text(last.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Button("Refresh now") {
                    Task { await sync.syncAll(reason: .manual) }
                }
                Button("Sign out", role: .destructive) {
                    Task {
                        await oauth.signOut()
                        dismiss()
                    }
                }
            }

            Section("Cloud API") {
                TextField("API base URL", text: $apiBase)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Stepper(value: $pollSeconds, in: 15...3600, step: 15) {
                    Text("Default poll: \(pollSeconds)s")
                }
                TextField("OAuth issuer override (optional)", text: $issuerOverride)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Save") {
                    saveConfig()
                }
                if let saveNote {
                    Text(saveNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Storage") {
                Text(CanvasStorage.applicationSupportRoot.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(Bundle.main.shortVersion)
                }
                Text("Subscribe cloud canvases to fixed widget slots. Add widgets from the Home Screen → Edit Widgets → Agent Canvas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func saveConfig() {
        var config = CloudConfigStore.load()
        config.apiBaseURL = apiBase
        config.defaultPollIntervalSeconds = max(15, pollSeconds)
        let trimmedIssuer = issuerOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        config.oauthIssuerOverride = trimmedIssuer.isEmpty ? nil : trimmedIssuer
        do {
            try config.save()
            saveNote = "Saved"
            sync.stopForegroundPolling()
            sync.startForegroundPolling()
        } catch {
            saveNote = error.localizedDescription
        }
    }
}

extension Bundle {
    var shortVersion: String {
        let ver = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(ver) (\(build))"
    }
}
