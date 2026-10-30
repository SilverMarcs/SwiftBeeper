import SwiftUI

struct BeeperSignInActionSection: View {
    let model: BeeperSignInModel

    var body: some View {
        Section {
            Button {
                Task { await model.submit() }
            } label: {
                Text(model.actionTitle)
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canSubmit)
        }
    }
}
