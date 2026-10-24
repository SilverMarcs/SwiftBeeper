import SwiftUI

struct BeeperSignInView: View {
    @Environment(SessionStore.self) private var sessionStore
    @State private var model: BeeperSignInModel

    init(startsWithRecoveryKey: Bool) {
        _model = State(initialValue: BeeperSignInModel(startsWithRecoveryKey: startsWithRecoveryKey))
    }

    var body: some View {
        VStack {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)

            Text("Sign in to Beeper")
                .font(.title.bold())

            switch model.step {
            case .email:
                BeeperEmailStepView(model: model)
            case .code:
                BeeperCodeStepView(model: model)
            case .recoveryKey:
                BeeperRecoveryStepView(model: model)
            }

            if model.isWorking {
                ProgressView(model.progressMessage)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(model.isWorking)
        .onChange(of: model.isFinished) { _, finished in
            if finished { sessionStore.isSignedIn = true }
        }
    }
}
