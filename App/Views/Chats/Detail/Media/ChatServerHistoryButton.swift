import SwiftUI

/// A toolbar button fetching one more page of older history from the server,
/// shown once a list has read everything stored locally.
struct ChatServerHistoryButton: View {
    let pager: ChatMessagePager

    var body: some View {
        if pager.canLoadServerHistory || pager.isLoadingServerHistory {
            Button("Load Older Messages", systemImage: "clock.arrow.circlepath") {
                Task { await pager.loadServerHistory() }
            }
            .disabled(pager.isLoadingServerHistory)
            .help("Load Older Messages")
        }
    }
}
