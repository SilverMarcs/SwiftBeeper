import SwiftUI

/// The inline composer used on macOS and iPad (the iPhone uses the navigation
/// bar's `.searchable` field instead — see `SearchFieldComposer`). All state lives in
/// `InputManager`; this view is just its presentation.
struct MessageInputView: View {
    @Environment(InputManager.self) private var input
    @Environment(ChatStore.self) private var chatStore

    @FocusState private var isMessageFieldFocused: Bool

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

                    TextField(
                        input.messageFieldPrompt,
                        text: Bindable(input).draft,
                        axis: .vertical
                    )
                        .textFieldStyle(.plain)
                        .focused($isMessageFieldFocused)
                        .lineLimit(1 ... 7)
                        .padding(.horizontal, 4)
                        .padding(8)
                        .glassEffect(in: .rect(cornerRadius: 20))
                        #if os(iOS)
                        .onGeometryChange(for: CGRect.self) { geometry in
                            geometry.frame(in: .global)
                        } action: { frame in
                            input.sendAnimator.sourceFrame = { frame }
                        }
                        #endif
                        .onSubmit(submit)

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
            if isMac {
                focusMessageField()
            }
        }
        .onChange(of: chatStore.activeComposerMessage?.id) { _, _ in
            focusMessageField()
        }
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

    private func focusMessageField() {
        // Wait a turn so focus lands after the current view update.
        Task {
            await Task.yield()
            isMessageFieldFocused = true
        }
    }
}
