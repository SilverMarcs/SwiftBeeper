import SwiftUI

struct MessageDeliveryStatusView: View {
    enum Status {
        case read
        case sending
        case failed(error: String, retry: () -> Void)
    }

    let status: Status

    var body: some View {
        Group {
            switch status {
            case .read:
                Text("Read")
                    .foregroundStyle(.secondary)
            case .sending:
                Text("Sending…")
                    .foregroundStyle(.secondary)
            case .failed(let error, let retry):
                Button("Not Delivered — Retry", action: retry)
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                    .help(error)
            }
        }
        .font(.caption2)
        .padding(.trailing, 3)
    }
}
