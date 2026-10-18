import SwiftUI

struct SignInRequiredView: View {
    var body: some View {
        ContentUnavailableView(
            "Sign in to Beeper",
            systemImage: "person.crop.circle",
            description: Text("Sign in to see your conversations.")
        )
    }
}
