import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// The inline composer used on macOS and iPad (the iPhone uses the navigation
/// bar's `.searchable` field instead — see `ChatDetailiOS`). All state lives in
/// `InputManager`; this view is just its presentation.
struct MessageInputView: View {
    @Environment(InputManager.self) private var input
    @Environment(ChatStore.self) private var chatStore

    @State private var showingFilePicker = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @FocusState private var isMessageFieldFocused: Bool

    var body: some View {
        if input.cannotMessage {
            cannotMessageView
        } else {
            inputView
        }
    }

    private var cannotMessageView: some View {
        Text("You can't message this person")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .glassEffect()
            .padding(.horizontal)
            .padding(.vertical, 10)
    }

    private var inputView: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                if let messagesError = chatStore.messagesError {
                    ComposerErrorBanner(message: messagesError)
                }

                if !input.pendingAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(input.pendingAttachments) { pending in
                                PendingAttachmentPreview(
                                    pending: pending,
                                    isSending: input.isSendingMessage,
                                    onRemove: { input.removePendingAttachment(id: pending.id) }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }

                HStack(alignment: .bottom) {
                    Menu {
                        Button {
                            showingPhotoPicker = true
                        } label: {
                            Label("Photos Library", systemImage: "photo.on.rectangle.angled")
                        }

                        Button {
                            showingFilePicker = true
                        } label: {
                            Label("Attach Files", systemImage: "paperclip")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.secondary, .clear)
                            .font(.largeTitle)
                            .glassEffect()
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .offset(y: -1)

                    if input.hasActiveComposerAction {
                        Button {
                            input.cancelComposerAction()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
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
                        text: input.draftBinding,
                        axis: .vertical
                    )
                        .textFieldStyle(.plain)
                        .focused($isMessageFieldFocused)
                        .lineLimit(1 ... 7)
                        .padding(.horizontal, 4)
                        .padding(8)
                        .glassEffect(in: .rect(cornerRadius: 16))
                        .onSubmit {
                            input.handleSubmit()
                        }

                    Button {
                        input.handleSubmit()
                    } label: {
                        Group {
                            if input.isSendingMessage {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: input.isEditing ? "checkmark" : "arrow.up")
                                    .font(.system(size: 15))
                                    .bold()
                            }
                        }
                    }
                    .opacity(input.sendButtonDisabled ? 0.35 : 0.85)
                    .controlSize(.large)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .allowsHitTesting(!input.sendButtonDisabled)
                    .offset(y: -2)
                }
                .padding(8)
                .padding(.horizontal, 2)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.item]
        ) { result in
            input.handleFileImport(result)
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotoItems,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: selectedPhotoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                for item in newItems {
                    await input.handlePhotoPick(item)
                }
            }
            selectedPhotoItems = []
        }
        #if os(macOS)
        .pasteHandler()
        #endif
        .onChange(of: chatStore.editingMessage?.id) { _, _ in
            input.editingMessageDidChange()
        }
        .onAppear {
            focusMessageField()
        }
        .onChange(of: chatStore.selectedChat?.id) { _, _ in
            focusMessageField()
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
                .disabled(input.cannotMessage)

                Button("Edit Last", systemImage: "pencil") {
                    input.editMostRecentOutgoingMessage()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(input.mostRecentEditableOutgoingMessage == nil)
            }
        }
        #endif
    }

    private func focusMessageField() {
        guard !input.cannotMessage else { return }
        Task { @MainActor in
            await Task.yield()
            isMessageFieldFocused = true
        }
    }
}
