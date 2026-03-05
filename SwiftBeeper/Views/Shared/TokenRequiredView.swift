import SwiftUI

struct TokenRequiredView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(description)
            )

            SettingsLink {
                Text("Open Settings")
            }
        }
    }
}

#Preview {
    TokenRequiredView(
        title: "Missing Token",
        systemImage: "key.fill",
        description: "Open Settings and add your Beeper bearer token."
    )
}
