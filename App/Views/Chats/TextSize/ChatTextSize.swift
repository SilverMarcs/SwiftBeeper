import SwiftUI

/// How big a chat draws its text on macOS, chosen from View > Zoom In and
/// Zoom Out. Stored as a step from the system's size, 0, each step one
/// body point size from `bodySizes`. The chat list keeps the system's size.
enum ChatTextSize {
    static let storageKey = "chatTextSize"

    /// The body text's point size at each step, smallest first. The system's
    /// 13pt is step 0.
    private static let bodySizes: [CGFloat] = [11, 12, 13, 14, 15, 16, 18, 20, 23, 26]
    private static let systemBodySize = Font.TextStyle.body.macPointSize
    private static let systemIndex = bodySizes.firstIndex(of: systemBodySize)!

    static let steps = (-systemIndex)...(bodySizes.count - 1 - systemIndex)

    /// How much a step scales every text style.
    static func scale(forStep step: Int) -> CGFloat {
        bodySizes[systemIndex + steps.clamp(step)] / systemBodySize
    }

    /// The chosen step, kept within `steps`.
    static var step: Int {
        get { steps.clamp(UserDefaults.standard.integer(forKey: storageKey)) }
        set { UserDefaults.standard.set(steps.clamp(newValue), forKey: storageKey) }
    }

    #if os(macOS)
    /// Zooms in on ⌘= as well as the menu's ⌘+. A menu item matches only the
    /// character it shows, so ⌘+ alone would need Shift on most layouts.
    static func zoomInOnUnshiftedPlus() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "=" else { return event }
            step += 1
            return nil
        }
    }
    #endif
}

private extension ClosedRange<Int> {
    func clamp(_ value: Int) -> Int {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}

extension EnvironmentValues {
    /// How much bigger than the system's sizes the chat draws its text; see
    /// `chatFont(_:design:)`.
    @Entry var chatTextScale: CGFloat = 1
}

extension View {
    /// Draws the chat at the text size chosen from the View menu on macOS.
    func chatTextSize() -> some View {
        #if os(macOS)
        modifier(ChatTextSizeEnvironment())
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct ChatTextSizeEnvironment: ViewModifier {
    @AppStorage(ChatTextSize.storageKey) private var step = 0

    func body(content: Content) -> some View {
        content.environment(\.chatTextScale, ChatTextSize.scale(forStep: step))
    }
}
#endif
