import SwiftUI

/// Keep a retry available when a bounded page contains only filtered events.
struct MessageHistoryControl: View {
    let isLoading: Bool
    let load: () -> Void

    var body: some View {
        HStack {
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button("Load Earlier Messages", action: load)
                    .font(.caption)
            }
            Spacer()
        }
    }
}
