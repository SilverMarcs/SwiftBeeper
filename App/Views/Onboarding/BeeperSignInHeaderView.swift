import SwiftUI

struct BeeperSignInHeaderView: View {
    @ScaledMetric(relativeTo: .title) private var iconSize = 80

    var body: some View {
        VStack {
            Image(.signInAppIcon)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .accessibilityHidden(true)

            Text("Sign in to Beeper")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }
}
