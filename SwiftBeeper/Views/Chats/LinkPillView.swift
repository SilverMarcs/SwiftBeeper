import SwiftUI

struct LinkPillView: View {
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(url.displayLabel)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .subtleBackground()
            .clipShape(.rect(cornerRadius: 12))
        }
    }
}

private extension URL {
    var displayLabel: String {
        var label = host() ?? absoluteString
        let trimmedPath = path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !trimmedPath.isEmpty {
            label += "/\(trimmedPath)"
        }
        return label
    }
}
