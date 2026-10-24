import SwiftUI

/// The first letters of up to two words of a name, or "?" for an empty name.
struct InitialsAvatarView: View {
    let name: String

    var body: some View {
        Circle()
            .fill(.quaternary)
            .overlay {
                Text(initials)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.primary)
            }
    }

    private var initials: String {
        let letters = name.trimmed.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined()
    }
}
