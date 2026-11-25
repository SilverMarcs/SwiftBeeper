import SwiftUI

/// Uses row identity on macOS so inspector and window resizing preserve the
/// reader's place as messages rewrap. iOS keeps its existing scroll reader.
struct TimelineScrollReader<Content: View>: View {
    let targetID: (String) -> String
    @ViewBuilder let content: (TimelineScrollProxy) -> Content
    #if os(macOS)
    @State private var position = ScrollPosition(idType: String.self)
    #endif

    var body: some View {
        #if os(macOS)
        content(TimelineScrollProxy { rowID, anchor in
            position.scrollTo(id: targetID(rowID), anchor: anchor)
        })
        .scrollPosition($position)
        #else
        ScrollViewReader(content: content)
        #endif
    }
}

#if os(macOS)
/// The shared timeline's navigation, backed by the platform's scroll API.
struct TimelineScrollProxy {
    let scroll: (String, UnitPoint?) -> Void

    func scrollTo(_ rowID: String, anchor: UnitPoint? = nil) {
        scroll(rowID, anchor)
    }
}
#else
typealias TimelineScrollProxy = ScrollViewProxy
#endif
