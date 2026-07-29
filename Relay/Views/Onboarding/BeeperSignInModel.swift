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
        await run {
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
        await run {
            let normalizedCode = code.filter(\.isNumber)
            let jwt = try await APIClient.beeperSubmitCode(
                domain: domain,
                request: requestID,
                code: normalizedCode
            )
            let homeserverURL = "https://matrix.\(domain)"
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
        await run {
            _ = try await APIClient.verifyRecoveryKey(recoveryKey)
            try await finish(sessionStore: sessionStore)
        }
    }

    func skipRecoveryKey(sessionStore: SessionStore) async {
        await run {
            try await finish(sessionStore: sessionStore)
        }
    }

    func useDifferentEmail() {
        code = ""
        errorMessage = nil
        step = .email
    }

    private func finish(sessionStore: SessionStore) async throws {
        let token: AccessTokenResponse
        do {
            token = try await APIClient.mintAccessToken()
        } catch {
            try await Task.sleep(for: .milliseconds(500))
            token = try await APIClient.mintAccessToken()
        }
        sessionStore.accessToken = token.accessToken
    }

    private func run(_ work: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}
