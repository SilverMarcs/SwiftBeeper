import SwiftUI

struct BeeperCodeStepView: View {
    @Bindable var model: BeeperSignInModel

    var body: some View {
        Section {
            TextField("Verification code", text: $model.code, prompt: Text("123456"))
                .textContentType(.oneTimeCode)
                .monospacedDigit()
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .disabled(model.step != .code)
                .onSubmit {
                    guard model.canSubmitCode else { return }
                    Task { await model.submitCode() }
                }
        } footer: {
            if model.step == .code {
                Text("Enter the six-digit code sent to your email.")
            }
        }
    }
}
