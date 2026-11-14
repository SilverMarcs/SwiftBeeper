import Foundation

extension Account {
    /// Slack's bridged Matrix receipts and subsequent replies are not
    /// evidence that another person has read a Slack message.
    var showsReadReceipts: Bool {
        let bridge = bridgeID.lowercased().replacing("local-", with: "")
        return bridge != "slack" && bridge != "slackgo"
    }
}
