import SwiftUI

/// A network filter's name, the login's name or network under it, and its
/// logo or workspace icon; a symbol stands in until the icon has loaded.
struct NetworkFilterLabel: View {
    let filter: NetworkFilter
    let icon: Image?

    var body: some View {
        Label {
            Text(filter.title)
            if let subtitle = filter.subtitle {
                Text(subtitle)
            }
        } icon: {
            if let icon {
                icon.renderingMode(.original)
            } else {
                Image(systemName: filter.systemImage)
            }
        }
    }
}
