import SwiftUI

/// Rows for the chat's shared photos and videos, files, and links, each
/// opening the full list.
struct ChatInfoMediaSection: View {
    /// Nil until the counts load; the rows show without them meanwhile.
    let info: ChatInfoOutput?

    var body: some View {
        Section {
            ForEach(ChatMediaKind.allCases, id: \.self) { kind in
                ChatInfoMediaRow(kind: kind, count: info?.count(of: kind))
            }
        }
    }
}
