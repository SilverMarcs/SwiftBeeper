import SwiftUI

/// Pick one chat, then send the shared item from the composer below the list.
struct ShareView: View {
    @State var model: ShareModel

    var body: some View {
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                ShareMacHeader(model: model)
                Divider()
                ShareChatList(model: model)
            }
            #else
            NavigationStack {
                ShareChatList(model: model)
                    .navigationTitle("Send To")
                    .navigationBarTitleDisplayMode(.inline)
                    .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .close) {
                                Task { await model.cancel() }
                            }
                        }
                    }
            }
            #endif
        }
        .task { await model.load() }
        .task(id: model.searchTrigger) { await model.search() }
        // Covers the sheet closing some other way; a no-op after Send or Cancel.
        .onDisappear {
            Task { await model.cancel() }
        }
    }
}
