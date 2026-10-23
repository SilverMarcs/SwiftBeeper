import SwiftUI

struct OnboardingView: View {
    @State private var needsRecovery = false

    var body: some View {
        BeeperSignInView(startsWithRecoveryKey: needsRecovery)
            .id(needsRecovery)
            .task {
                if let state = try? await APIClient.manageState() {
                    needsRecovery = state.clientState?.isLoggedIn == true && state.clientState?.isVerified != true
                }
            }
    }
}

#Preview {
    OnboardingView()
        .environment(SessionStore())
}
