#if os(iOS)
import SwiftUI

/// iPhone's composer, for a chat or a thread: the navigation search field,
/// with Return sending, Close keeping the draft, attachments in the bottom
/// bar, and reply/edit state tied to the search session.
struct SearchFieldComposer: ViewModifier {
    @Environment(DictationSettings.self) private var dictationSettings
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var inputManager

    let composer: Composer
    let chat: Chat

    @FocusState private var isFocused: Bool
    @State private var isPresented = false
    @State private var delegateProxy: TextFieldDelegateProxy?
    @State private var searchBarDelegateProxy: SearchBarDelegateProxy?
    @State private var searchField = ComposerSearchFieldReference()
    @State private var dictationFocusTask: Task<Void, Never>?
    @State private var attachmentFocusTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            // The timeline's bottom edge sits just above the native composer.
            .composerMentionPopover(composer, isFocused: isFocused, restoreCursor: restoreMentionCursor)
            .searchable(text: Bindable(composer).text, isPresented: $isPresented, prompt: Text(composer.prompt))
            .autocorrectionDisabled(false)
            .textInputAutocapitalization(.sentences)
            .searchFocused($isFocused)
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .background(
                SearchIntrospector { configure($0, searchBar: $1, referenceView: $2) }
                    .onGeometryChange(for: CGRect.self) { geometry in
                        geometry.frame(in: .global)
                    } action: { frame in
                        composer.searchReferenceFrame = frame
                    }
            )
            // A change, not the current value: the request is shared by every
            // chat, and the composer of a chat opened later must not replay it.
            .onChange(of: composer.dictationFocusRequestID) {
                dictationFocusTask?.cancel()
                // Not cancelled on disappear: the detail view can disappear and
                // reappear while it settles, which would drop the request.
                dictationFocusTask = Task {
                    await focusAfterDictation()
                }
            }
            // Return is the Send key; keep it lit while attachments are pending.
            .onChange(of: composer.pendingAttachments.isEmpty, initial: true) { _, isEmpty in
                SendableSearchTextField.hasPendingAttachments = !isEmpty
                refreshReturnKey()
            }
            // Adding an attachment returns to the composer, so a caption can be
            // typed. Removing one leaves focus alone.
            .onChange(of: composer.pendingAttachments.count) { oldCount, newCount in
                guard newCount > oldCount else { return }
                attachmentFocusTask?.cancel()
                attachmentFocusTask = Task {
                    // Let the picker or camera finish dismissing first, or it
                    // takes the keyboard back.
                    do {
                        try await Task.sleep(for: .milliseconds(400))
                    } catch {
                        return
                    }
                    await focusAfterDictation()
                }
            }
            .onSubmit(of: .search) {
                inputManager.submit(composer)
                isFocused = true
            }
            // Mirror focus into the composer, where the timeline observes it to
            // scroll to the latest message (FocusState is view-local).
            .onChange(of: isFocused) { _, focused in
                composer.isFocused = focused
                // The Return key's attachment flag is shared with the other
                // composer, such as a thread's sheet over the chat.
                if focused {
                    SendableSearchTextField.hasPendingAttachments = !composer.pendingAttachments.isEmpty
                    refreshReturnKey()
                }
            }
            // Another chat's composer can take over this field.
            .onChange(of: composer.target) { oldTarget, _ in
                let previous = inputManager.composer(for: oldTarget)
                previous.isFocused = false
                composer.isFocused = isFocused
                composer.searchReferenceFrame = previous.searchReferenceFrame
            }
            // Leaving the chat can tear the field down while it still has
            // focus; the next chat's first focus must register as a change.
            .onDisappear {
                attachmentFocusTask?.cancel()
                composer.isFocused = false
            }
            .onChange(of: composer.isSavingEdit) { oldValue, newValue in
                if oldValue && !newValue {
                    isFocused = true
                }
            }
            // Reply and Edit come from a context menu. Focus after it has
            // dismissed, or its keyboard restore resigns the field while the
            // search stays presented. A thread's composer appears after its
            // Reply, so this also runs for a request made before it existed.
            .task(id: composer.focusRequestID) {
                guard composer.focusRequestID != nil else { return }
                do {
                    try await Task.sleep(for: InputManager.contextMenuDismissalDelay)
                } catch {
                    return
                }
                isPresented = true
                await Task.yield()
                isFocused = true
                composer.didHandleFocusRequest()
            }
            .onChange(of: isPresented) { _, presented in
                // Reply/edit and search are entered together, so Cancel leaves
                // both. A bare keyboard dismissal keeps the search presented,
                // so this only fires on a real search exit.
                guard !presented, composer.activeMessage != nil else { return }
                inputManager.cancelAction(in: composer)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    MessagePendingAttachmentsBar(composer: composer)
                    if composer.target.isThread && !composer.isEditing && chatStore.repliesInThreads(in: chat) {
                        AlsoSendToChatToggle(isOn: Bindable(composer).alsoSendToChat, chat: chat)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    AttachmentMenu(composer: composer) {
                        Label("Attach", systemImage: "plus")
                    }
                    .menuIndicator(.hidden)
                }
                ToolbarSpacer(.fixed, placement: .bottomBar)
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                if dictationSettings.isEnabled {
                    ToolbarItem(placement: .bottomBar) {
                        ComposerDictationButton(composer: composer)
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

    /// Makes the keyboard re-read whether Return is enabled.
    private func refreshReturnKey() {
        guard let textField = searchField.textField, let referenceView = searchField.referenceView else { return }
        for field in [textField] + composerFields(matching: textField, referenceView: referenceView)
        where field.isFirstResponder {
            field.reloadInputViews()
        }
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
        for field in [textField] + composerFields(matching: textField, referenceView: referenceView) {
            SendableSearchTextField.install(on: field)
        }
        composer.sourceFrame = { [weak composer, weak textField, weak referenceView] in
            guard let composer, let textField, let referenceView,
                  textField.window != nil, !textField.isHidden else { return nil }
            let frame = textField.convert(textField.bounds, to: referenceView)
            let reference = composer.searchReferenceFrame
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
                    dx: composer.searchReferenceFrame.minX,
                    dy: composer.searchReferenceFrame.minY
                )
            }
            inputManager.submit(composer, sourceFrame: sourceFrame)
            return false
        }
        delegateProxy?.selectionDidChange = { field in
            guard let text = field.text, let range = field.selectedTextRange else { return }
            let selection = NSRange(
                location: field.offset(from: field.beginningOfDocument, to: range.start),
                length: field.offset(from: range.start, to: range.end)
            )
            Task { @MainActor [weak field] in
                await Task.yield()
                guard field?.text == text, composer.text == text else { return }
                composer.selection = selection
            }
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

    private func restoreMentionCursor(_ offset: Int) {
        let insertedDraft = composer.text
        isFocused = true
        // Updating searchable text can move the cursor to the end. Restore it
        // after SwiftUI applies the draft, including its visible field clone.
        Task { @MainActor in
            await Task.yield()
            guard composer.text == insertedDraft else { return }
            guard let field = searchField.textField, let reference = searchField.referenceView else { return }
            for field in [field] + composerFields(matching: field, referenceView: reference) where field.isFirstResponder {
                field.text = composer.text
                if let cursor = field.position(from: field.beginningOfDocument, offset: offset) {
                    field.selectedTextRange = field.textRange(from: cursor, to: cursor)
                }
            }
        }
    }

    /// Shows the draft in composer fields UIKit emptied while closing.
    private func restoreDraft(in textField: UISearchTextField, referenceView: UIView) {
        ComposerSearchFields.restore(composer.text, matching: textField, referenceView: referenceView)
    }

    private func styleComposerFields(in textField: UISearchTextField, referenceView: UIView) {
        ComposerSearchFields.style(matching: textField, referenceView: referenceView)
    }

    /// `textField` and every clone of it UIKit shows.
    private func composerFields(matching textField: UISearchTextField, referenceView: UIView) -> [UISearchTextField] {
        ComposerSearchFields.fields(matching: textField, referenceView: referenceView)
    }
}

extension View {
    /// Turns the navigation search field into the conversation's composer (iPhone).
    func searchFieldComposer(_ composer: Composer, chat: Chat) -> some View {
        modifier(SearchFieldComposer(composer: composer, chat: chat))
    }
}
#endif
