#if DEBUG
import SwiftUI

/// The lab's chat list, standing in for `RootView`.
struct TimelineLabRootView: View {
    @State private var controller = TimelineLabController.shared

    var body: some View {
        NavigationStack(path: $controller.path) {
            List(TimelineLabFixture.allCases) { fixture in
                Button(fixture.title) { controller.open(fixture) }
            }
            .navigationTitle("Timeline Lab")
            .navigationDestination(for: String.self) { key in
                if let source = controller.sources[key] {
                    TimelineLabChatScreen(source: source)
                }
            }
        }
        #if os(iOS)
        .task { await TimelineLabProbe.run() }
        #endif
    }
}
#endif
