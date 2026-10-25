#if os(iOS)
import SwiftUI

/// iPhone's composer: the navigation search field, with Return sending,
/// attachments in the bottom bar, and reply/edit state tied to the search session.
struct SearchFieldComposer: ViewModifier {
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var inputManager

    @FocusState private var isFocused: Bool
    @State private var isPresented = false
    @State private var delegateProxy: TextFieldDelegateProxy?

    func body(content: Content) -> some View {
        content
            .onChange(of: chatStore.editingMessage?.id) { _, _ in
                inputManager.editingMessageDidChange()
            }
            .searchable(text: Bindable(inputManager).draft, isPresented: $isPresented, prompt: Text(inputManager.messageFieldPrompt))
            .searchFocused($isFocused)
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .background(
                SearchIntrospector { configure($0, referenceView: $1) }
                    .onGeometryChange(for: CGRect.self) { geometry in
                        geometry.frame(in: .global)
                    } action: { frame in
                        inputManager.sendAnimator.searchReferenceFrame = frame
                    }
            )
            .onSubmit(of: .search) {
                inputManager.handleSubmit()
                isFocused = true
            }
            // Mirror focus into InputManager, where the timeline observes it to
            // scroll to the latest message (FocusState is view-local).
            .onChange(of: isFocused) { _, focused in
                inputManager.isComposerFocused = focused
            }
            // Leaving the chat can tear the field down while it still has
            // focus; the next chat's first focus must register as a change.
            .onDisappear {
                inputManager.isComposerFocused = false
            }
            .onChange(of: chatStore.isSavingEdit) { oldValue, newValue in
                if oldValue && !newValue {
                    isFocused = true
                }
            }
            .onChange(of: chatStore.activeComposerMessage?.id) { _, newValue in
                // Entering reply/edit state.
                guard newValue != nil else { return }
                isFocused = true
            }
            .onChange(of: isPresented) { _, presented in
                // Reply/edit and search are entered together, so Cancel leaves
                // both. A bare keyboard dismissal keeps the search presented,
                // so this only fires on a real search exit.
                guard !presented, chatStore.activeComposerMessage != nil else { return }
                inputManager.cancelComposerAction()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MessagePendingAttachmentsBar()
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    AttachmentMenu {
                        Label("Attach", systemImage: "plus")
                    }
                    .menuIndicator(.hidden)
                }
                ToolbarSpacer(.fixed, placement: .bottomBar)
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
    }

    /// Makes Return send, gives the send animation its source frame, and
    /// intercepts Return through a delegate proxy.
    private func configure(_ textField: UISearchTextField, referenceView: UIView) {
        if textField.returnKeyType != .send {
            textField.returnKeyType = .send
            if textField.isFirstResponder {
                textField.reloadInputViews()
            }
        }
        let animator = inputManager.sendAnimator
        animator.sourceFrame = { [weak animator, weak textField, weak referenceView] in
            guard let animator, let textField, let referenceView,
                  textField.window != nil, !textField.isHidden else { return nil }
            let frame = textField.convert(textField.bounds, to: referenceView)
            let reference = animator.searchReferenceFrame
            return frame.offsetBy(dx: reference.minX, dy: reference.minY)
        }
        if delegateProxy == nil || textField.delegate !== delegateProxy {
            let proxy = TextFieldDelegateProxy(originalDelegate: textField.delegate)
            textField.delegate = proxy
            delegateProxy = proxy
        }
        // Use the field that received Return, even if SwiftUI has replaced
        // the searchable field.
        delegateProxy?.shouldReturn = { [weak referenceView] field in
            let sourceFrame = referenceView.map {
                field.convert(field.bounds, to: $0).offsetBy(
                    dx: animator.searchReferenceFrame.minX,
                    dy: animator.searchReferenceFrame.minY
                )
            }
            inputManager.handleSubmit(sourceFrame: sourceFrame)
            return false
        }
    }
}

extension View {
    /// Turns the navigation search field into the message composer (iPhone).
    func searchFieldComposer() -> some View {
        modifier(SearchFieldComposer())
    }
}

/// Answers Return itself and forwards every other delegate call to the field's
/// original (SwiftUI-owned) delegate.
private final class TextFieldDelegateProxy: NSObject, UITextFieldDelegate {
    weak var originalDelegate: UITextFieldDelegate?
    var shouldReturn: ((UITextField) -> Bool)?

    init(originalDelegate: UITextFieldDelegate?) {
        self.originalDelegate = originalDelegate
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(textFieldShouldReturn(_:)) {
            return true
        }
        return originalDelegate?.responds(to: aSelector) ?? super.responds(to: aSelector)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        originalDelegate
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let shouldReturn {
            return shouldReturn(textField)
        }
        return originalDelegate?.textFieldShouldReturn?(textField) ?? true
    }
}
#endif
