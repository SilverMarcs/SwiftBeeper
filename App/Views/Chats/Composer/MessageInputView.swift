#if os(macOS)
import SwiftUI

/// The inline composer on macOS (iPhone and iPad use `ComposerBar`). State
/// lives in the conversation's `Composer`; this view is just its presentation.
struct MessageInputView: View {
    @Environment(InputManager.self) private var input
    @Environment(ChatStore.self) private var chatStore

    let composer: Composer
    let chat: Chat
    /// The conversation's failure, shown above the field.
    let error: String?

    @FocusState private var isMessageFieldFocused: Bool
    @State private var selection: TextSelection?
    /// Where a sent bubble flies from. Kept here rather than on the composer:
    /// the field stays put while another chat's composer takes it over, so its
    /// frame wouldn't change to reach the new one.
    @State private var fieldFrame: CGRect?

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

                    if composer.activeMessage != nil {
                        Button {
                            input.cancelAction(in: composer)
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.7), .clear)
                                .glassEffect(.regular.tint(.red.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                        .offset(y: -1)
                        .scaleEffect(0.9)
                    }

                    HStack(alignment: .bottom, spacing: 0) {
                        TextField(
                            composer.prompt,
                            text: Bindable(composer).text,
                            selection: $selection,
                            axis: .vertical
                        )
                            .textFieldStyle(.plain)
                            .focused($isMessageFieldFocused)
                            .lineLimit(1 ... 7)
                            .padding(.horizontal, 4)
                            .padding(8)
                            .onGeometryChange(for: CGRect.self) { geometry in
                                geometry.frame(in: .global)
                            } action: { frame in
                                fieldFrame = frame
                            }
                            .onSubmit(submit)
                            // Return sends; Shift-Return starts a new line. The
                            // field treats both as submit unless intercepted.
                            .onKeyPress(.return, phases: [.down, .repeat]) { press in
                                guard press.modifiers.contains(.shift) else { return .ignored }
                                NSApp.sendAction(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil)
                                return .handled
                            }
                            .composerMentionPopover(composer, isFocused: isMessageFieldFocused, restoreCursor: restoreMentionCursor)

                        ComposerDictationButton(composer: composer, isInline: true)
                            .buttonStyle(.plain)
                    }
                    .glassEffect(in: .rect(cornerRadius: 20))

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
        .onChange(of: selection) { _, newValue in
            updateComposerSelection(newValue)
        }
        // Mirror focus into the composer so the timeline can scroll when the
        // keyboard appears (FocusState is view-local).
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
            selection = nil
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
        input.submit(composer, sourceFrame: fieldFrame)
    }

    private func restoreMentionCursor(_ offset: Int) {
        guard let range = Range(NSRange(location: offset, length: 0), in: composer.text) else { return }
        selection = TextSelection(insertionPoint: range.lowerBound)
        focusMessageField()
    }

    private func updateComposerSelection(_ newValue: TextSelection?) {
        Task { @MainActor in
            // Selection can arrive while the text binding is still writing.
            // Wait for that write, then use only the latest selection.
            await Task.yield()
            guard selection == newValue else { return }
            let text = composer.text
            guard let newValue, case .selection(let range) = newValue.indices,
                  range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else { return }
            composer.selection = NSRange(range, in: text)
        }
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
