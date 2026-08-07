import SwiftUI

struct HowToView: View {
    var body: some View {
        List {
            Section("Get started") {
                labeled("1", "Sign in with your Velox account.")
                labeled("2", "Tap + and paste a canvas slug or API URL, then pick a slot.")
                labeled(
                    "3",
                    "On the Home Screen, long-press → Edit Widgets → add an Agent Canvas size/slot that matches."
                )
                labeled("4", "Open the app anytime to sync; background refresh keeps tiles roughly current.")
            }
            Section("Tips") {
                Text("Widgets are fixed addresses (sm-one, md-two, …). Subscribe the same id you place on the Home Screen.")
                Text("Public canvases work signed out for fetch, but sign-in is required for private/org canvases.")
            }
        }
        .navigationTitle("How to Use")
    }

    private func labeled(_ step: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.headline)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.body)
        }
        .padding(.vertical, 4)
    }
}
