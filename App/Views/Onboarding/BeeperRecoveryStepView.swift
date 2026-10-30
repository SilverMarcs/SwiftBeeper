import SwiftUI

struct BeeperRecoveryStepView: View {
    @Bindable var model: BeeperSignInModel

    var body: some View {
        Section {
            SecureField("Recovery key", text: $model.recoveryKey)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
                #endif
                .autocorrectionDisabled()
                .onSubmit {
                    guard model.canSubmitRecoveryKey else { return }
                    Task { await model.submitRecoveryKey() }
                }
        } footer: {
            Text("Paste your recovery key to decrypt encrypted chats.")
        }
    }
}
