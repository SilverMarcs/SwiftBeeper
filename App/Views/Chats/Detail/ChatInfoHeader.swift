import SwiftUI

/// A large avatar, title, and one-line summary at the top of an info screen.
struct ChatInfoHeader<Avatar: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let avatar: Avatar

    var body: some View {
        VStack(spacing: 4) {
            avatar
                .padding(.bottom, 8)

            Text(title)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
