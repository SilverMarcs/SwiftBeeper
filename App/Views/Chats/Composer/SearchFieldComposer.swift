#if os(iOS)
import SwiftUI

/// iPhone's composer: the navigation search field, with Return sending,
/// Close keeping the draft, attachments in the bottom bar, and reply/edit
/// state tied to the search session.
struct SearchFieldComposer: ViewModifier {
    @Environment(DictationSettings.self) private var dictationSettings
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var inputManager

    @FocusState private var isFocused: Bool
    @State private var isPresented = false
    @State private var delegateProxy: TextFieldDelegateProxy?
    @State private var searchBarDelegateProxy: SearchBarDelegateProxy?
    @State private var searchField = ComposerSearchFieldReference()
    @State private var composerActionFocusTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onChange(of: chatStore.editingMessage?.id) { _, _ in
                inputManager.editingMessageDidChange()
            }
            .searchable(text: Bindable(inputManager).draft, isPresented: $isPresented, prompt: Text(inputManager.messageFieldPrompt))
            .autocorrectionDisabled(false)
            .textInputAutocapitalization(.sentences)
            .searchFocused($isFocused)
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .background(
                SearchIntrospector { configure($0, searchBar: $1, referenceView: $2) }
                    .onGeometryChange(for: CGRect.self) { geometry in
                        geometry.frame(in: .global)
                    } action: { frame in
                        inputManager.sendAnimator.searchReferenceFrame = frame
                    }
            )
            .task(id: inputManager.dictationFocusRequestID) {
                guard inputManager.dictationFocusRequestID != nil else { return }
                await focusAfterDictation()
            }
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
                composerActionFocusTask?.cancel()
                inputManager.isComposerFocused = false
            }
            .onChange(of: chatStore.isSavingEdit) { oldValue, newValue in
                if oldValue && !newValue {
                    isFocused = true
                }
            }
            .onChange(of: chatStore.activeComposerMessage?.id) { _, newValue in
                composerActionFocusTask?.cancel()
                // Entering reply/edit state. Focus after the context menu has
                // dismissed, or its keyboard restore resigns the field while
                // the search stays presented.
                guard newValue != nil else { return }
                composerActionFocusTask = Task {
                    do {
                        try await Task.sleep(for: InputManager.contextMenuDismissalDelay)
                    } catch {
                        return
                    }
                    isFocused = true
                }
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
                if dictationSettings.isEnabled {
                    ToolbarItem(placement: .bottomBar) {
                        ComposerDictationButton()
                    }
                }
            }
    }

    /// Opens the composer with its keyboard once a transcript lands in the
    /// draft. A field already being typed in is left undisturbed.
    private func focusAfterDictation() async {
        guard !isComposerFieldEditing else { return }
        if isFocused {
            // Tapping a toolbar button resigns the native field while the
            // focus binding stays true, so writing true again changes nothing.
            // Clear it, and let SwiftUI apply that before refocusing.
            isFocused = false
            do {
                try await Task.sleep(for: .milliseconds(1))
            } catch {
                return
            }
        }
        isPresented = true
        // Let the search field open before requesting its keyboard.
        await Task.yield()
        guard !Task.isCancelled else { return }
        isFocused = true
    }

    /// Whether any field showing this composer has the keyboard.
    private var isComposerFieldEditing: Bool {
        guard let textField = searchField.textField, let referenceView = searchField.referenceView else { return false }
        return composerFields(matching: textField, referenceView: referenceView).contains(where: \.isFirstResponder)
    }

    /// Closes the composer and its keyboard, keeping the draft for later.
    ///
    /// SwiftUI's own Close handling empties the search text, so this stands in
    /// for it. UIKit still empties the field as the search deactivates, and
    /// SwiftUI only pushes the draft into it when the draft changes, so the
    /// draft is put back once UIKit is done.
    private func close(_ textField: UISearchTextField, referenceView: UIView) {
        withAnimation {
            isPresented = false
        }
        Task {
            restoreDraft(in: textField, referenceView: referenceView)
        }
    }

    /// Makes Return send and Close keep the draft, by intercepting them
    /// through delegate proxies, and gives the send animation its source frame.
    private func configure(_ textField: UISearchTextField, searchBar: UISearchBar?, referenceView: UIView) {
        searchField.textField = textField
        searchField.referenceView = referenceView
        if textField.returnKeyType != .send {
            textField.returnKeyType = .send
            if textField.isFirstResponder {
                textField.reloadInputViews()
            }
        }
        styleComposerFields(in: textField, referenceView: referenceView)
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
        if let searchBar {
            if searchBarDelegateProxy == nil || searchBar.delegate !== searchBarDelegateProxy {
                let proxy = SearchBarDelegateProxy(originalDelegate: searchBar.delegate)
                searchBar.delegate = proxy
                searchBarDelegateProxy = proxy
            }
            searchBarDelegateProxy?.cancelButtonClicked = { [weak textField, weak referenceView] _ in
                guard let textField, let referenceView else { return }
                close(textField, referenceView: referenceView)
            }
        }
        restoreDraft(in: textField, referenceView: referenceView)
    }

    /// Shows the draft in composer fields UIKit emptied while closing. Fields
    /// being edited are left alone, as they already hold what was typed.
    private func restoreDraft(in textField: UISearchTextField, referenceView: UIView) {
        for field in composerFields(matching: textField, referenceView: referenceView)
        where !field.isFirstResponder && field.text != inputManager.draft {
            field.text = inputManager.draft
        }
    }

    /// Uses regular body text and removes the magnifying glass, since this field
    /// composes messages. A zero-size leading view replaces the glyph so its slot
    /// takes no width; merely hiding the glyph keeps the slot.
    ///
    /// The bottom-bar field UIKit draws is a clone of `textField` that doesn't
    /// follow the original's icon, so every field showing this composer's
    /// prompt is updated directly. The chat list's "Search chats" field never
    /// shares that prompt.
    private func styleComposerFields(in textField: UISearchTextField, referenceView: UIView) {
        for field in composerFields(matching: textField, referenceView: referenceView)
        where !(field.leftView is ComposerSearchFieldStyle) {
            field.leftView = ComposerSearchFieldStyle(textField: field)
        }
    }

    /// `textField` and every clone of it UIKit shows, told apart by this
    /// composer's prompt.
    private func composerFields(matching textField: UISearchTextField, referenceView: UIView) -> [UISearchTextField] {
        guard let prompt = textField.placeholder, let window = referenceView.window else { return [] }
        return ([textField] + searchTextFields(in: window)).filter { $0.placeholder == prompt }
    }

    private func searchTextFields(in view: UIView) -> [UISearchTextField] {
        if let field = view as? UISearchTextField {
            return [field]
        }
        return view.subviews.flatMap(searchTextFields(in:))
    }
}

extension View {
    /// Turns the navigation search field into the message composer (iPhone).
    func searchFieldComposer() -> some View {
        modifier(SearchFieldComposer())
    }
}
#endif
