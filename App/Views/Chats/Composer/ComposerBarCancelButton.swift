#if os(iOS)
import SwiftUI

/// The glass circle after the attachment button while replying or editing,
/// which leaves the reply or edit.
struct ComposerBarCancelButton: View {
    let cancel: () -> Void

    var body: some View {
        Button("Cancel", systemImage: "xmark", action: cancel)
            .labelStyle(.iconOnly)
            .font(.title3)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
    }
}
#endif
