import SwiftUI

/// An equal-width tile with an icon over a short title, filled like the form rows below it.
struct ChatInfoActionLabel: View {
    let title: String
    let systemImage: String

    private static let cornerRadius: CGFloat = Device.isMac ? 10 : 20

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(height: 24)
            Text(title)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.formRowBackground, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
        .contentShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
    }
}
