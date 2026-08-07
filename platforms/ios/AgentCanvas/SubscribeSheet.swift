import SwiftUI

struct SubscribeSheet: View {
    var initialSlug: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sync: SubscriptionSync
    @EnvironmentObject private var router: DeepLinkRouter

    @State private var slugOrURL: String = ""
    @State private var selected: CanvasAddress = .mdOne
    @State private var errorText: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Cloud canvas") {
                    TextField("Slug or API URL", text: $slugOrURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section("Slot") {
                    Picker("Canvas slot", selection: $selected) {
                        ForEach(CanvasAddress.allCases) { address in
                            Text("\(address.displayName) (\(address.rawValue))")
                                .tag(address)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Subscribe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        router.subscribeSlug = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Subscribe") {
                        Task { await subscribe() }
                    }
                    .disabled(busy || slugOrURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay {
                if busy {
                    ProgressView()
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .onAppear {
                if slugOrURL.isEmpty, !initialSlug.isEmpty {
                    slugOrURL = initialSlug
                }
            }
        }
    }

    private func subscribe() async {
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            try await sync.subscribe(slugOrURL: slugOrURL, address: selected)
            router.subscribeSlug = nil
            dismiss()
            router.openDetail(selected)
        } catch {
            errorText = CloudAPIClient.userFacingMessage(for: error)
        }
    }
}
