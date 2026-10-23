import SwiftUI

struct BeeperCodeStepView: View {
    @Bindable var model: BeeperSignInModel

    var body: some View {
        VStack {
            Text("Enter the six-digit code sent to **\(model.email)**.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            TextField("123456", text: $model.code)
                .textFieldStyle(.roundedBorder)
                .font(.title3.monospacedDigit())
                .multilineTextAlignment(.center)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onSubmit {
                    guard model.canSubmitCode else { return }
                    Task { await model.submitCode() }
                }

            Button("Verify") {
                Task { await model.submitCode() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canSubmitCode)

            Button("Use a Different Email") {
                model.useDifferentEmail()
            }
            .buttonStyle(.plain)
        }
    }
}
