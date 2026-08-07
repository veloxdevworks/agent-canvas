import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var oauth: VeloxOAuthSession
    @State private var errorText: String?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.tint)
                Text("Agent Canvas")
                    .font(.largeTitle.weight(.bold))
                Text("Sign in with Velox to subscribe cloud canvases to home screen widgets.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else if let err = oauth.lastError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    Task { await signIn() }
                } label: {
                    if oauth.isBusy {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign in with Velox")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(oauth.isBusy)
                .padding(.horizontal, 32)

                Spacer()
                Text(CloudConfigStore.load().normalizedAPIBase)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 16)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
    }

    private func signIn() async {
        errorText = nil
        do {
            try await oauth.signIn(config: CloudConfigStore.load())
        } catch {
            errorText = error.localizedDescription
        }
    }
}
