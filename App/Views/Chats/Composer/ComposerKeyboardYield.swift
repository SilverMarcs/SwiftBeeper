#if os(iOS)
import SwiftUI
import UIKit

/// Takes the composer out of the way while another field has the keyboard,
/// such as the emoji keyboard of a reaction or, on iPad, the chat list's
/// search field or a thread's composer, so only the composer's own focus
/// raises it above the keyboard.
///
/// The timeline still keeps clear of the keyboard, so the message being
/// reacted to stays in view; the composer's share of the safe area folds
/// away instead of riding up with a keyboard it doesn't use. The composer
/// stays in the hierarchy, keeping its editor, draft, and focus handling.
struct ComposerKeyboardYield: ViewModifier {
    let composer: Composer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isYielding = false

    func body(content: Content) -> some View {
        // The composer's own focus always shows it, however the keyboard's
        // announcements and the focus mirror happened to interleave.
        let isHidden = isYielding && !composer.isFocused
        content
            .frame(height: isHidden ? 0 : nil, alignment: .top)
            .opacity(isHidden ? 0 : 1)
            .allowsHitTesting(!isHidden)
            .accessibilityHidden(isHidden)
            // UIKit announces the editor gaining or losing focus before the
            // keyboard that follows, so a keyboard showing while the composer
            // isn't focused belongs to another field. Leaving the composer for
            // the emoji keyboard announces it again for the new field.
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                guard !composer.isFocused else { return }
                setYielding(true)
            }
            // The composer losing focus keeps its place until its keyboard has
            // gone, so it rides the keyboard down rather than dropping behind it.
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                setYielding(false)
            }
            // Focus, such as Reply's, brings it back for the keyboard to raise,
            // and keeps it back once that keyboard is gone.
            .onChange(of: composer.isFocused) { _, focused in
                if focused { isYielding = false }
            }
    }

    private func setYielding(_ yielding: Bool) {
        guard isYielding != yielding, !(yielding && composer.isFocused) else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
            isYielding = yielding
        }
    }
}

extension View {
    /// Folds the composer away while another field has the keyboard.
    func yieldsKeyboardToOtherFields(_ composer: Composer) -> some View {
        modifier(ComposerKeyboardYield(composer: composer))
    }
}
#endif
