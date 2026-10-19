import Foundation

enum SignInPresentation {
    static func help(for step: BeeperSignInStep, email: String) -> String {
        switch step {
        case .email: "Enter the email address for your Beeper account."
        case .code: "Enter the six-digit code sent to \(email)."
        case .recoveryKey: "Paste your recovery key to decrypt encrypted chats. You can add it later if needed."
        }
    }
    static func button(for step: BeeperSignInStep) -> String {
        switch step { case .email: "Send Code"; case .code: "Verify"; case .recoveryKey: "Verify and Continue" }
    }
}
