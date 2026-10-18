import SwiftUI

struct BeeperEmailStepView: View {
    @Bindable var model: BeeperSignInModel

    var body: some View {
        VStack {
            Text("Enter the email address for your Beeper account.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            TextField("you@example.com", text: $model.email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
                .autocorrectionDisabled()
                .onSubmit {
                    guard model.canSendCode else { return }
                    Task { await model.sendCode() }
                }

            Button("Send Code") {
                Task { await model.sendCode() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canSendCode)
        }
    }
}
