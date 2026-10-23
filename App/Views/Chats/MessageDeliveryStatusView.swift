import SwiftUI

struct MessageDeliveryStatusView: View {
    enum Status {
        case read
        case failed(messageID: OutgoingMessage.ID, error: String)
    }

    @Environment(ChatStore.self) private var chatStore

    let status: Status

    var body: some View {
        Group {
            switch status {
            case .read:
                Text("Read")
                    .foregroundStyle(.secondary)
            case .failed(let messageID, let error):
                Button("Not Delivered — Retry") {
                    chatStore.retrySending(messageID)
                }
                .foregroundStyle(.red)
                .buttonStyle(.plain)
                .help(error)
            }
        }
        .font(.caption2)
        .padding(.trailing, 3)
    }
}
