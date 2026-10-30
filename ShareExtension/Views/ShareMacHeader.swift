#if os(macOS)
import SwiftUI

/// The title, Cancel, and search field. A share sheet on macOS has no window
/// toolbar for `searchable` and toolbar items to use.
struct ShareMacHeader: View {
    @Bindable var model: ShareModel

    var body: some View {
        VStack {
            HStack {
                Text("Send To")
                    .font(.headline)
                Spacer()
                Button("Cancel", role: .cancel) {
                    Task { await model.cancel() }
                }
                .keyboardShortcut(.cancelAction)
            }
            TextField("Search", text: $model.query)
                .textFieldStyle(.roundedBorder)
        }
        .padding()
    }
}
#endif
