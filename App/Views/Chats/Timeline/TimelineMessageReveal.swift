import SwiftUI

/// A reveal belongs to this viewport and request. Switching chats, windows
/// or targets cancels it before it can scroll or complete another request.
struct TimelineMessageReveal<Source: TimelineSource>: ViewModifier {
    let source: Source
    let entries: [TimelineEntry]
    let proxy: ScrollViewProxy
    let frames: TimelineRowFrames
    let topInset: CGFloat
    let willReveal: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let isPreparing = source.messageRevealRequest?.alignsTop == true
        content
            // Lay out and position the normal page before revealing it. The
            // reader never sees its temporary bottom-anchored first frame.
            .opacity(isPreparing ? 0 : 1)
            .allowsHitTesting(!isPreparing)
            .accessibilityHidden(isPreparing)
            .overlay {
                if isPreparing { ProgressView() }
            }
            .task(id: source.messageRevealRequest) {
                guard let request = source.messageRevealRequest, source.hasLoadedTimeline else { return }
                guard entries.contains(where: { $0.messages.contains { $0.id == request.messageID } }) else {
                    source.finishMessageReveal(request, reached: false)
                    return
                }
                let rowID = TimelineEntry.rowID(for: request.messageID, in: entries)
                do {
                    try await Task.sleep(for: .milliseconds(request.alignsTop ? 50 : 150))
                    guard source.messageRevealRequest?.id == request.id else { return }
                    willReveal()
                    let anchor: UnitPoint = request.alignsTop ? .top : .center
                    withAnimation(reduceMotion || request.alignsTop ? nil : .easeInOut(duration: 0.3)) {
                        proxy.scrollTo(rowID, anchor: anchor)
                    }
                    try await Task.sleep(for: .milliseconds(request.alignsTop ? 50 : 350))
                    guard source.messageRevealRequest?.id == request.id else { return }
                    if !frames.isVisible(rowID, below: topInset) {
                        // A lazy row can settle after the first scroll resolves.
                        // Retry once at its measured position without animation.
                        proxy.scrollTo(rowID, anchor: anchor)
                        try await Task.sleep(for: .milliseconds(100))
                        guard source.messageRevealRequest?.id == request.id else { return }
                    }
                    let reached = frames.isVisible(rowID, below: topInset)
                    source.finishMessageReveal(request, reached: reached)
                } catch {
                    // Cancellation leaves the new viewport and request alone.
                }
            }
    }
}
