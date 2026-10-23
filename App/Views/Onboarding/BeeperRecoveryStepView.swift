import SwiftUI

struct BeeperRecoveryStepView: View {
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
                    Task { await model.submitRecoveryKey() }
                }

            Button("Verify and Continue") {
                Task { await model.submitRecoveryKey() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canSubmitRecoveryKey)
        }
    }
}
