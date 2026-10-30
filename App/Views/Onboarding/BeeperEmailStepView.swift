import SwiftUI

struct BeeperEmailStepView: View {
    @Bindable var model: BeeperSignInModel

    var body: some View {
        Section {
            TextField("Email", text: $model.email, prompt: Text("you@example.com"))
                .textContentType(.emailAddress)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
                .autocorrectionDisabled()
                .disabled(model.step != .email)
                .onSubmit {
                    guard model.canSendCode else { return }
                    Task { await model.sendCode() }
                }
        } footer: {
            if model.step == .email {
                Text("Enter the email address for your Beeper account.")
            } else if model.step == .code {
                Button("Use a Different Email", action: model.useDifferentEmail)
            }
        }
    }
}
