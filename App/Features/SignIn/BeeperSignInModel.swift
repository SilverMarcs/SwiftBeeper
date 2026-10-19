import Foundation
import Observation

@MainActor
@Observable
final class BeeperSignInModel {
    var step: BeeperSignInStep
    var domain = "beeper.com"
    var email = ""
    var requestID = ""
    var code = ""
    var recoveryKey = ""
    var isWorking = false
    var progressMessage = ""
    var errorMessage: String?

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
        recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines).count >= 16
            && !isWorking
    }

    func sendCode() async {
        await run("Sending your sign-in code…") {
            requestID = try await APIClient.beeperStartLogin(domain: domain)
            try await APIClient.beeperRequestCode(
                domain: domain,
                request: requestID,
                email: email
            )
            step = .code
        }
    }

    func submitCode(sessionStore: SessionStore) async {
        await run("Checking your code…") {
            let normalizedCode = code.filter(\.isNumber)
            let jwt = try await APIClient.beeperSubmitCode(
                domain: domain,
                request: requestID,
                code: normalizedCode
            )
            let homeserverURL = "https://matrix.\(domain)"
            progressMessage = "Connecting your account…"
            let state = try await APIClient.loginCustomJWT(
                homeserverURL: homeserverURL,
                jwt: jwt
            )
            if state.clientState?.isVerified == true {
                try await finish(sessionStore: sessionStore)
            } else {
                step = .recoveryKey
            }
        }
    }

    func submitRecoveryKey(sessionStore: SessionStore) async {
        await run("Restoring your encryption keys…") {
            let key = recoveryKey
            _ = try await APIClient.verifyRecoveryKey(key)
            recoveryKey = ""
            try await finish(sessionStore: sessionStore)
        }
    }

    func useDifferentEmail() {
        code = ""
        errorMessage = nil
        step = .email
    }

    private func finish(sessionStore: SessionStore) async throws {
        sessionStore.accessToken = try MatrixFiles.configuration().accessToken
        await MatrixRuntime.shared.setActive(true)
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
