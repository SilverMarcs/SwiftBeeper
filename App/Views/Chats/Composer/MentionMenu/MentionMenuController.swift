#if os(macOS)
import AppKit
import SwiftUI

/// Presents the macOS mention menu beside the @ being typed, as a menu that
/// leaves the keyboard with the composer: letters keep narrowing the list,
/// while Up and Down (or Control-P and Control-N) move the highlight, Return
/// or Tab inserts the highlighted member, and Escape closes it.
///
/// A real `NSMenu` can't do this: it tracks the keyboard itself while open.
/// The keys are read ahead of the window, so the window's own shortcuts,
/// such as Escape cancelling a reply, wait until the menu has closed.
@MainActor
final class MentionMenuController {
    /// The editor the menu belongs to, set as it's made.
    weak var editor: MacComposerEditor?

    private let state = MentionMenuState()
    private var panel: MentionMenuPanel?
    /// Where the @ is in the editor's text, while the menu is presented.
    private var anchor: Int?
    private var onSelect: ((ChatParticipant) -> Void)?
    private var onDismiss: (() -> Void)?
    private var keyMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    /// Lists `participants` beside the @ at `location`, moving the menu to
    /// follow it.
    func show(
        _ participants: [ChatParticipant],
        anchoredAt location: Int,
        select: @escaping (ChatParticipant) -> Void,
        dismiss: @escaping () -> Void
    ) {
        guard let editor, editor.window != nil, !participants.isEmpty else {
            close()
            return
        }
        let wasPresented = anchor != nil
        state.show(participants)
        anchor = location
        onSelect = select
        onDismiss = dismiss
        let panel = panel ?? MentionMenuPanel(rootView: rootView)
        self.panel = panel
        panel.hostingView.rootView = rootView
        if !wasPresented { startTracking(editor) }
        attach()
    }

    func close() {
        guard anchor != nil else { return }
        anchor = nil
        onSelect = nil
        onDismiss = nil
        detach()
        stopTracking()
    }

    private var rootView: MentionMenuView {
        MentionMenuView(participants: state.participants, state: state) { [weak self] participant in
            self?.onSelect?(participant)
        }
    }

    // MARK: Placement

    /// Shows the panel over the editor's window while that window is key.
    private func attach() {
        guard anchor != nil, let panel, let window = editor?.window, window.isKeyWindow else {
            detach()
            return
        }
        reposition()
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    private func detach() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// Sits the menu just above the line with the @, its names lined up with
    /// the @, or below the line when there's no room above.
    private func reposition() {
        guard let editor, let anchor, let panel, anchor < (editor.string as NSString).length,
              let screen = editor.window?.screen ?? NSScreen.main else { return }
        let size = panel.hostingView.fittingSize
        let line = editor.firstRect(forCharacterRange: NSRange(location: anchor, length: 1), actualRange: nil)
        let visible = screen.visibleFrame
        var origin = NSPoint(
            x: line.minX - MentionMenuMetrics.nameOffset,
            y: line.maxY + MentionMenuMetrics.lineSpacing
        )
        if origin.y + size.height > visible.maxY {
            origin.y = line.minY - MentionMenuMetrics.lineSpacing - size.height
        }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        let frame = NSRect(origin: origin, size: size).integral
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    // MARK: Tracking

    /// Follows the editor as it grows, scrolls, and reflows, its window as
    /// it gains and loses key, and the keyboard.
    private func startTracking(_ editor: MacComposerEditor) {
        let center = NotificationCenter.default
        let reposition: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        var views: [NSView] = [editor]
        if let scrollView = editor.enclosingScrollView {
            views.append(scrollView)
            scrollView.contentView.postsBoundsChangedNotifications = true
            observers.append(center.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main, using: reposition
            ))
        }
        for view in views {
            view.postsFrameChangedNotifications = true
            observers.append(center.addObserver(
                forName: NSView.frameDidChangeNotification, object: view, queue: .main, using: reposition
            ))
        }
        if let window = editor.window {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.attach() }
                })
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
    }

    private func stopTracking() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Handles a key meant for the menu, leaving the rest to the editor. A
    /// composition, such as Japanese input, keeps every key.
    private func handle(_ event: NSEvent) -> Bool {
        guard let editor, let panel, panel.isVisible, event.window === editor.window,
              editor.window?.firstResponder === editor, !editor.hasMarkedText() else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = event.specialKey
        if modifiers.isEmpty, key == .upArrow || key == .downArrow {
            state.moveHighlight(by: key == .upArrow ? -1 : 1)
        } else if modifiers == .control, let letter = event.charactersIgnoringModifiers, letter == "p" || letter == "n" {
            state.moveHighlight(by: letter == "p" ? -1 : 1)
        } else if modifiers.isEmpty, key == .carriageReturn || key == .enter || key == .tab {
            guard let highlighted = state.highlighted else { return false }
            onSelect?(highlighted)
        } else if modifiers.isEmpty, event.keyCode == Self.escapeKeyCode {
            onDismiss?()
        } else {
            return false
        }
        return true
    }

    private static let escapeKeyCode: UInt16 = 53
}
#endif
