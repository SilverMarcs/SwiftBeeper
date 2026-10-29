import SwiftUI

/// The inline composer used on macOS and iPad (the iPhone uses the navigation
/// bar's `.searchable` field instead — see `SearchFieldComposer`). All state lives in
/// `InputManager`; this view is just its presentation.
struct MessageInputView: View {
    @Environment(InputManager.self) private var input
    @Environment(ChatStore.self) private var chatStore

    @FocusState private var isMessageFieldFocused: Bool
    @State private var selection: TextSelection?

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                if let messagesError = chatStore.messagesError {
                    ComposerErrorBanner(message: messagesError)
                }

                MessagePendingAttachmentsBar()

                HStack(alignment: .bottom) {
                    AttachmentMenu {
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
                    #if os(macOS)
                    .offset(y: -1)
                    #else
                    .scaleEffect(0.97)
                    #endif

                    if chatStore.activeComposerMessage != nil {
                        Button {
                            input.cancelComposerAction()
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
                            input.messageFieldPrompt,
                            text: Bindable(input).draft,
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
                                input.sendAnimator.sourceFrame = { frame }
                            }
                            .onSubmit(submit)
                            .composerMentionPopover(isFocused: isMessageFieldFocused, restoreCursor: restoreMentionCursor)

                        ComposerDictationButton(isInline: true)
                            .buttonStyle(.plain)
                    }
                    .glassEffect(in: .rect(cornerRadius: 20))

                    ComposerSendButton(submit: submit)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                #if os(macOS)
                .padding(.bottom, 12)
                #else
                .padding(.bottom, isMessageFieldFocused ? 8 : 0)
                #endif
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        #if os(macOS)
        .pasteHandler()
        #endif
        .onChange(of: chatStore.editingMessage?.id) { _, _ in
            input.editingMessageDidChange()
        }
        .onChange(of: selection) { _, newValue in
            updateComposerSelection(newValue)
        }
        // Mirror focus into InputManager so the iPad detail view can scroll
        // the timeline when the keyboard appears (FocusState is view-local).
        .onChange(of: isMessageFieldFocused) { _, focused in
            input.isComposerFocused = focused
        }
        #if !os(macOS)
        .onChange(of: chatStore.isSavingEdit) { oldValue, newValue in
            if oldValue && !newValue {
                focusMessageField()
            }
        }
        #endif
        .onAppear {
            if isMac {
                focusMessageField()
            }
        }
        .onChange(of: chatStore.selectedChat?.id) { _, _ in
            selection = nil
            if isMac {
                focusMessageField()
            }
        }
        .onChange(of: chatStore.activeComposerMessage?.id) { _, newValue in
            #if os(iOS)
            // Entering reply/edit from a context menu: focusing before the
            // menu has dismissed is undone by its keyboard restore.
            if newValue != nil {
                focusMessageField(after: InputManager.contextMenuDismissalDelay)
                return
            }
            #endif
            focusMessageField()
        }
        #if os(macOS)
        .task(id: input.dictationFocusRequestID) {
            guard input.dictationFocusRequestID != nil, !isMessageFieldFocused else { return }
            // Leave an already focused field and its keyboard undisturbed.
            await Task.yield()
            guard !Task.isCancelled, !isMessageFieldFocused else { return }
            isMessageFieldFocused = true
        }
        #endif
        .onChange(of: input.pendingFocus) { _, newValue in
            if newValue {
                input.pendingFocus = false
                focusMessageField()
            }
        }
        #if os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("Focus", systemImage: "text.cursor") {
                    focusMessageField()
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Edit Last", systemImage: "pencil") {
                    input.editMostRecentOutgoingMessage()
                }
                .keyboardShortcut("e", modifiers: .command)
            }
        }
        #endif
    }

    /// Sends or saves the draft. iOS keeps the keyboard up for the next message.
    private func submit() {
        input.handleSubmit()
        #if !os(macOS)
        focusMessageField()
        #endif
    }

    private func restoreMentionCursor(_ offset: Int) {
        guard let range = Range(NSRange(location: offset, length: 0), in: input.draft) else { return }
        selection = TextSelection(insertionPoint: range.lowerBound)
        focusMessageField()
    }

    private func updateComposerSelection(_ newValue: TextSelection?) {
        let chatID = input.selectedChatID
        Task { @MainActor in
            // Selection can arrive while the text binding is still writing.
            // Wait for that write, then use only the latest selection.
            await Task.yield()
            guard input.selectedChatID == chatID, selection == newValue else { return }
            let text = input.draft
            guard let newValue, case .selection(let range) = newValue.indices,
                  range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else { return }
            input.composerSelection = NSRange(range, in: text)
        }
    }

    private func focusMessageField(after delay: Duration = .zero) {
        // Wait at least a turn so focus lands after the current view update.
        Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            } else {
                await Task.yield()
            }
            isMessageFieldFocused = true
        }
    }
}
