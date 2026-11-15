#if os(iOS)
import SwiftUI
import UIKit

/// Places the composer independently of the timeline's keyboard safe area.
/// Another field's keyboard covers the resting bar instead of collapsing it;
/// the timeline continues to keep its messages above that keyboard.
struct TimelineComposerBar: ViewModifier {
    let composer: Composer
    let chat: Chat
    let error: String?

    @State private var isYielding = false
    @State private var composerHeight: CGFloat = 0
    @State private var composerTop: CGFloat = 0
    @State private var safeAreaBottom: CGFloat = 0

    func body(content: Content) -> some View {
        // The composer's own focus always shows it, however the keyboard's
        // announcements and the focus mirror happened to interleave.
        let staysAtBottom = isYielding && !composer.isFocused
        // The bar and timeline rise together for this composer's keyboard,
        // so clearance depends only on its height. Their screen positions
        // arrive in separate layout passes and can briefly disagree, causing
        // the inset to collapse at the start of keyboard movement.
        // Only another field's keyboard needs an overlap calculation: a
        // docked keyboard covers the resting bar; a floating one leaves it.
        let reservedHeight = staysAtBottom
            ? max(0, min(composerHeight, safeAreaBottom - composerTop))
            : composerHeight
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: reservedHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay {
                // A flexible layer can extend past the keyboard safe area;
                // ignoring it on the fixed-height bar alone cannot do that.
                Color.clear
                    .allowsHitTesting(false)
                    .overlay(alignment: .bottom) {
                        ComposerBar(composer: composer, chat: chat, error: error, avoidsKeyboard: !staysAtBottom)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                composerHeight = $0
                            }
                            .onGeometryChange(for: CGFloat.self) {
                                staysAtBottom ? $0.frame(in: .global).minY : 0
                            } action: {
                                composerTop = $0
                            }
                    }
                    .ignoresSafeArea(staysAtBottom ? .keyboard : [], edges: .bottom)
            }
            .onGeometryChange(for: CGFloat.self) {
                staysAtBottom ? $0.frame(in: .global).maxY - $0.safeAreaInsets.bottom : 0
            } action: {
                safeAreaBottom = $0
            }
            // UIKit announces the editor gaining or losing focus before the
            // keyboard that follows, so a keyboard showing while the composer
            // isn't focused belongs to another field. Leaving the composer for
            // the emoji keyboard announces it again for the new field.
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                guard !composer.isFocused else { return }
                isYielding = true
            }
            // The composer losing focus keeps its place until its keyboard has
            // gone, so it rides the keyboard down rather than dropping behind it.
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                isYielding = false
            }
            // Focus, such as Reply's, brings it back for the keyboard to raise,
            // and keeps it back once that keyboard is gone.
            .onChange(of: composer.isFocused) { _, focused in
                if focused { isYielding = false }
            }
    }
}

extension View {
    /// Keeps the composer at rest when another field owns the keyboard.
    func timelineComposerBar(_ composer: Composer, chat: Chat, error: String?) -> some View {
        modifier(TimelineComposerBar(composer: composer, chat: chat, error: error))
    }
}
#endif
