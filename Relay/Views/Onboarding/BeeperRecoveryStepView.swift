import SwiftUI

struct BeeperRecoveryStepView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Bindable var model: BeeperSignInModel

    var body: some View {
        VStack {
            Text("Paste your recovery key to decrypt encrypted chats. You can add it later if needed.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            SecureField("Recovery key", text: $model.recoveryKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    guard model.canSubmitRecoveryKey else { return }
                    Task {
                        await model.submitRecoveryKey(sessionStore: sessionStore)
                    }
                }

            Button("Verify and Continue") {
                Task {
                    await model.submitRecoveryKey(sessionStore: sessionStore)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canSubmitRecoveryKey)

            Button("Skip for Now") {
                Task {
                    await model.skipRecoveryKey(sessionStore: sessionStore)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
