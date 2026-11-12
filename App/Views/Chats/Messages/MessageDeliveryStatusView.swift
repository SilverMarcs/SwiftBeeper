import SwiftUI

/// The caption under an outgoing message that didn't get through: a bridge's
/// refusal, or a failed send's retry. Progress is `DeliveryCaptionView`.
struct MessageDeliveryStatusView: View {
    enum Status: Equatable {
        /// The bridge couldn't deliver a message the homeserver accepted.
        case notDelivered(error: String?)
        /// The homeserver never accepted it; sending again may.
        case failed(messageID: OutgoingMessage.ID, error: String)
    }

    @Environment(ChatStore.self) private var chatStore

    let status: Status

    var body: some View {
        Group {
            switch status {
            case .notDelivered(let error):
                Text("Not Delivered")
                    .foregroundStyle(.red)
                    .help(error ?? "")
                    .accessibilityHint(error ?? "")
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
