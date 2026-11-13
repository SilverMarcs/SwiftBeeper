#if os(iOS)
import SwiftUI

/// The glass circle before the composer bar's field, opening the attachment
/// menu.
struct ComposerBarAttachButton: View {
    let composer: Composer

    var body: some View {
        AttachmentMenu(composer: composer) {
            Label("Attach", systemImage: "plus")
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.circle)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }
}
#endif
