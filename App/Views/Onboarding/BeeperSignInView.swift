import SwiftUI

struct BeeperSignInView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SessionStore.self) private var sessionStore
    @State private var model: BeeperSignInModel
    @State private var formHeight: CGFloat?

    init(startsWithRecoveryKey: Bool) {
        _model = State(initialValue: BeeperSignInModel(startsWithRecoveryKey: startsWithRecoveryKey))
    }

    var body: some View {
        Form {
            Section {
                BeeperSignInHeaderView()
            }
            .listRowBackground(Color.clear)

            Group {
                if model.step != .recoveryKey || !model.email.isEmpty {
                    BeeperEmailStepView(model: model)
                }

                if model.step == .code || !model.code.isEmpty {
                    BeeperCodeStepView(model: model)
                }

                if model.step == .recoveryKey {
                    BeeperRecoveryStepView(model: model)
                }

                if let errorMessage = model.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }

                BeeperSignInActionSection(model: model)
            }
            .listRowBackground(Rectangle().fill(.background.secondary))
        }
        .formStyle(.grouped)
        .scrollContentBackground(colorScheme == .dark ? .visible : .hidden)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .contentMargins(.bottom, 24, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
        } action: { _, height in
            if height > 0 { formHeight = height }
        }
        .frame(minHeight: 0, idealHeight: formHeight, maxHeight: formHeight)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .disabled(model.isWorking)
        .onChange(of: model.isFinished) { _, finished in
            if finished { sessionStore.isSignedIn = true }
        }
    }
}
