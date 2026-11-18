#if os(macOS)
import SwiftUI

/// The inline composer on macOS (iPhone and iPad use `ComposerBar`). State
/// lives in the conversation's `Composer`; this view is just its presentation.
struct MessageInputView: View {
    @Environment(InputManager.self) private var input
    @Environment(ChatStore.self) private var chatStore
    @Environment(DictationSettings.self) private var dictationSettings

    let composer: Composer
    let chat: Chat
    /// The conversation's failure, shown above the field.
    let error: String?

    /// Whether the editor is first responder, mirrored into the composer.
    @State private var isMessageFieldFocused = false
    /// The field and editor a sent bubble grows out of. Kept here rather than on
    /// the composer: the field stays put while another chat's composer takes
    /// it over, so its frame wouldn't change to reach the new one.
    @State private var sendOrigin = ComposerSendOrigin(fieldCornerRadius: Self.fieldCornerRadius)
    /// The mention menu at the editor's @, kept with the editor it follows.
    @State private var mentionMenu = MentionMenuController()

    private static let fieldCornerRadius: CGFloat = 20

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                if let error {
                    ComposerErrorBanner(message: error)
                }

                MessagePendingAttachmentsBar(composer: composer)

                if composer.target.isThread && !composer.isEditing && chatStore.repliesInThreads(in: chat) {
                    AlsoSendToChatToggle(isOn: Bindable(composer).alsoSendToChat, chat: chat)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                HStack(alignment: .bottom) {
                    AttachmentMenu(composer: composer) {
                        Label("Attach", systemImage: "plus.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary, .clear)
                            .font(.largeTitle)
                            .glassEffect()
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .offset(y: -1)

                    HStack(alignment: .bottom, spacing: 0) {
                        MacComposerTextView(
                            text: Bindable(composer).text,
                            isFocused: $isMessageFieldFocused,
                            sendOrigin: sendOrigin,
                            mentionMenu: mentionMenu,
                            selection: composer.selection,
                            mentions: composer.draft.mentions.map(\.range),
                            placeholder: composer.prompt,
                            onSelectionChange: { composer.selection = $0 },
                            onReturn: submit
                        )
                            .onGeometryChange(for: CGRect.self) { geometry in
                                geometry.frame(in: .global)
                            } action: { frame in
                                sendOrigin.editorFrame = frame
                            }
                            .padding(.vertical, 8)
                            .padding(.leading, 12)
                            // The dictation button's own margin spaces the
                            // text from it; without it, the field's edge does.
                            .padding(.trailing, dictationSettings.isEnabled ? 0 : 12)
                            .composerMentionMenu(composer, isFocused: isMessageFieldFocused, menu: mentionMenu) { _ in
                                // The mention's insertion already placed the caret.
                                focusMessageField()
                            }

                        ComposerDictationButton(composer: composer, isInline: true)
                            .buttonStyle(.plain)
                    }
                    .glassEffect(in: .rect(cornerRadius: Self.fieldCornerRadius))
                    .onGeometryChange(for: CGRect.self) { geometry in
                        geometry.frame(in: .global)
                    } action: { frame in
                        sendOrigin.fieldFrame = frame
                    }

                    ComposerSendButton(
                        isEditing: composer.isEditing,
                        isSaving: composer.isSavingEdit,
                        isDisabled: !input.canSubmit(composer),
                        submit: submit
                    )
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .pasteHandler(composer)
        // Mirror focus into the composer, which paste and the timeline read.
        // The field keeps its own, as another chat's composer can take it over.
        .onChange(of: isMessageFieldFocused) { _, focused in
            composer.isFocused = focused
        }
        .onDisappear {
            composer.isFocused = false
        }
        .onAppear {
            focusMessageField()
        }
        .onChange(of: composer.target) { oldTarget, _ in
            // The field stays while another chat's composer takes it over.
            input.composer(for: oldTarget).isFocused = false
            composer.isFocused = isMessageFieldFocused
            focusMessageField()
        }
        // Reply, Edit, and notification drafts ask for focus.
        .task(id: composer.focusRequestID) {
            guard composer.focusRequestID != nil else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            isMessageFieldFocused = true
            composer.didHandleFocusRequest()
        }
        .onChange(of: composer.activeMessage?.id) { _, newValue in
            // Leaving reply or edit returns to the draft, unless a closed
            // thread's hidden composer is the one leaving.
            if newValue == nil, !composer.target.isThread || chatStore.isThreadPresented {
                focusMessageField()
            }
        }
        .task(id: composer.dictationFocusRequestID) {
            guard composer.dictationFocusRequestID != nil, !isMessageFieldFocused else { return }
            // Leave an already focused field and its keyboard undisturbed.
            await Task.yield()
            guard !Task.isCancelled, !isMessageFieldFocused else { return }
            isMessageFieldFocused = true
        }
        .toolbar {
            // One set of shortcuts, for the chat's own composer.
            if !composer.target.isThread {
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Focus", systemImage: "text.cursor") {
                        focusMessageField()
                    }
                    .keyboardShortcut("l", modifiers: .command)

                    Button("Edit Last", systemImage: "pencil") {
                        input.editMostRecentOutgoingMessage(in: composer)
                    }
                    .keyboardShortcut("e", modifiers: .command)
                }
            }
        }
    }

    /// Sends or saves the draft.
    private func submit() {
        input.submit(composer, from: sendOrigin)
    }

    private func focusMessageField() {
        // Wait a turn so focus lands after the current view update.
        Task {
            await Task.yield()
            isMessageFieldFocused = true
        }
    }
}
#endif
