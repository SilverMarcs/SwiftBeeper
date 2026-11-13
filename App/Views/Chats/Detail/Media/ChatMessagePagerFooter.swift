import SwiftUI

/// The end of a paged list: a spinner while a page loads, or the last error.
struct ChatMessagePagerFooter: View {
    let pager: ChatMessagePager

    var body: some View {
        VStack {
            if pager.isLoading || pager.isLoadingServerHistory {
                ProgressView()
            }

            if let errorMessage = pager.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
