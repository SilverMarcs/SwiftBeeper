import SwiftUI

/// Sits above the oldest local message once local pages run out. Local pages
/// load on scroll; server history loads one page per press.
struct LoadServerHistoryButton: View {
    let load: () async -> Void

    var body: some View {
        Button("Load Older History", systemImage: "clock.arrow.circlepath") {
            Task { await load() }
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }
}
