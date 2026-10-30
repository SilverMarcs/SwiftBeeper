import Foundation
import Observation

/// Beeper's email-code sign-in, followed by the recovery key when the
/// session can't decrypt yet.
@MainActor
@Observable
final class BeeperSignInModel {
    enum Step {
        case email
        case code
        case recoveryKey
    }

    private(set) var step: Step
    var email = ""
    var code = ""
    var recoveryKey = ""
    private(set) var isWorking = false
    private(set) var progressMessage = ""
    private(set) var errorMessage: String?
    /// Set once the account is signed in and verified; the view then opens Relay.
    private(set) var isFinished = false
    private let domain = "beeper.com"
    private var requestID = ""

    init(startsWithRecoveryKey: Bool) {
        step = startsWithRecoveryKey ? .recoveryKey : .email
    }

    var canSendCode: Bool {
        email.localizedStandardContains("@") && !isWorking
    }

    var canSubmitCode: Bool {
        code.filter(\.isNumber).count >= 6 && !isWorking
    }

    var canSubmitRecoveryKey: Bool {
        recoveryKey.trimmed.count >= 16 && !isWorking
    }

    var actionTitle: String {
        if isWorking { return progressMessage }
        return switch step {
        case .email: "Send Code"
        case .code: "Verify"
        case .recoveryKey: "Verify and Continue"
        }
    }

    var canSubmit: Bool {
        switch step {
        case .email: canSendCode
        case .code: canSubmitCode
        case .recoveryKey: canSubmitRecoveryKey
        }
    }

    func submit() async {
        guard canSubmit else { return }
        switch step {
        case .email: await sendCode()
        case .code: await submitCode()
        case .recoveryKey: await submitRecoveryKey()
        }
    }

    func sendCode() async {
        await run("Sending your sign-in code…") {
            requestID = try await APIClient.beeperStartLogin(domain: domain)
            try await APIClient.beeperRequestCode(domain: domain, request: requestID, email: email)
            step = .code
        }
    }

    func submitCode() async {
        await run("Checking your code…") {
            let jwt = try await APIClient.beeperSubmitCode(
                domain: domain,
                request: requestID,
                code: code.filter(\.isNumber)
            )
            progressMessage = "Connecting your account…"
            let state = try await APIClient.loginCustomJWT(homeserverURL: "https://matrix.\(domain)", jwt: jwt)
            if state.isVerified {
                isFinished = true
            } else {
                step = .recoveryKey
            }
        }
    }

    func submitRecoveryKey() async {
        await run("Restoring your encryption keys…") {
            _ = try await APIClient.verifyRecoveryKey(recoveryKey)
            recoveryKey = ""
            isFinished = true
        }
    }

    func useDifferentEmail() {
        code = ""
        errorMessage = nil
        step = .email
    }

    private func run(_ message: String, _ work: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        progressMessage = message
        defer { isWorking = false; progressMessage = "" }
        errorMessage = nil
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
