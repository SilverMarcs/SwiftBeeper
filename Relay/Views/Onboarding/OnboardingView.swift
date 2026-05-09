import SwiftUI

struct OnboardingView: View {
    @Environment(SessionStore.self) private var sessionStore

    private enum Step: Equatable {
        case email
        case code
        case recoveryKey
    }

    @State private var step: Step = .email
    @State private var domain: String = "beeper.com"
    @State private var email: String = ""
    @State private var requestID: String = ""
    @State private var code: String = ""
    @State private var recoveryKey: String = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Sign in to Beeper")
                .font(.title2.bold())

            Group {
                switch step {
                case .email: emailStep
                case .code: codeStep
                case .recoveryKey: recoveryStep
                }
            }
            .frame(maxWidth: 360)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(isWorking)
    }

    private var emailStep: some View {
        VStack(spacing: 16) {
            Text("Enter the email address for your Beeper account.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            TextField("you@example.com", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .disableAutocorrection(true)
                .onSubmit { Task { await sendCode() } }
            Button(action: { Task { await sendCode() } }) {
                stepLabel("Send code")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!email.contains("@") || isWorking)
        }
    }

    private var codeStep: some View {
        VStack(spacing: 16) {
            Text("Enter the 6-digit code sent to **\(email)**.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            TextField("123456", text: $code)
                .textFieldStyle(.roundedBorder)
                .font(.title3.monospacedDigit())
                .multilineTextAlignment(.center)
                .onSubmit { Task { await submitCode() } }
            Button(action: { Task { await submitCode() } }) {
                stepLabel("Verify")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(code.filter(\.isNumber).count < 6 || isWorking)
            Button("Use a different email") {
                code = ""
                errorMessage = nil
                step = .email
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
    }

    private var recoveryStep: some View {
        VStack(spacing: 16) {
            Text("Paste your recovery key to decrypt encrypted chats. You can skip this and add it later.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            SecureField("EsT… (recovery key)", text: $recoveryKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await submitRecoveryKey() } }
            Button(action: { Task { await submitRecoveryKey() } }) {
                stepLabel("Verify and continue")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(recoveryKey.trimmingCharacters(in: .whitespaces).count < 16 || isWorking)
            Button("Skip for now") {
                Task { await finish() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func stepLabel(_ title: String) -> some View {
        if isWorking {
            ProgressView().controlSize(.small)
        } else {
            Text(title).frame(maxWidth: .infinity)
        }
    }

    private func sendCode() async {
        await run {
            requestID = try await APIClient.beeperStartLogin(domain: domain)
            try await APIClient.beeperRequestCode(domain: domain, request: requestID, email: email)
            step = .code
        }
    }

    private func submitCode() async {
        await run {
            let normalizedCode = code.filter(\.isNumber)
            let jwt = try await APIClient.beeperSubmitCode(domain: domain, request: requestID, code: normalizedCode)
            let homeserverURL = "https://matrix.\(domain)"
            let state = try await APIClient.loginCustomJWT(homeserverURL: homeserverURL, jwt: jwt)
            if state.clientState?.isVerified == true {
                await finish()
            } else {
                step = .recoveryKey
            }
        }
    }

    private func submitRecoveryKey() async {
        await run {
            _ = try await APIClient.verifyRecoveryKey(recoveryKey)
            await finish()
        }
    }

    private func finish() async {
        await run {
            let token: AccessTokenResponse
            do {
                token = try await APIClient.mintAccessToken()
            } catch {
                try await Task.sleep(for: .milliseconds(500))
                token = try await APIClient.mintAccessToken()
            }
            sessionStore.accessToken = token.accessToken
        }
    }

    private func run(_ work: @escaping () async throws -> Void) async {
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

#Preview {
    OnboardingView()
        .environment(SessionStore())
}
