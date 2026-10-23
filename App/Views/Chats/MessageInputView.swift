import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// The inline composer used on macOS and iPad (the iPhone uses the navigation
/// bar's `.searchable` field instead — see `ChatTimelineView`). All state lives in
/// `InputManager`; this view is just its presentation.
struct MessageInputView: View {
    @Environment(InputManager.self) private var input
    @Environment(ChatStore.self) private var chatStore

    @State private var showingFilePicker = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var attachmentTargetChatID: String?
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
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(input.pendingAttachments) { pending in
                                PendingAttachmentPreview(
                                    pending: pending,
                                    isSending: false,
                                    onRemove: { input.removePendingAttachment(id: pending.id) }
                                )
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }

                HStack(alignment: .bottom) {
                    Menu {
                        Button {
                            attachmentTargetChatID = chatStore.selectedChatID
                            showingPhotoPicker = true
                        } label: {
                            Label("Photos Library", systemImage: "photo.on.rectangle.angled")
                        }

                        Button {
                            attachmentTargetChatID = chatStore.selectedChatID
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
                    #if os(macOS)
                    .offset(y: -1)
                    #else
                    .scaleEffect(0.97)
                    #endif


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
                        .glassEffect(in: .rect(cornerRadius: 20))
                        #if os(iOS)
                        .onGeometryChange(for: CGRect.self) { geometry in
                            geometry.frame(in: .global)
                        } action: { frame in
                            input.sendAnimator.sourceFrame = { frame }
                        }
                        #endif
                        .onSubmit {
                            input.handleSubmit()
                            #if !os(macOS)
                            focusMessageField()
                            #endif
                        }

                    Button {
                        input.handleSubmit()
                        #if !os(macOS)
                        focusMessageField()
                        #endif
                    } label: {
                        Group {
                            if input.isSavingEdit {
                                ProgressView()
                                    #if os(macOS)
                                    .controlSize(.small)
                                    #endif
                            } else {
                                Image(systemName: input.isEditing ? "checkmark" : "arrow.up")
                                    #if os(macOS)
                                    .font(.system(size: 15))
                                    #else
                                    .font(.title3)
                                    #endif
                                    .bold()
                            }
                        }
                    }
                    .opacity(input.sendButtonDisabled ? 0.35 : 0.85)
                    #if os(macOS)
                    .controlSize(.large)
                    #endif
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .allowsHitTesting(!input.sendButtonDisabled)
                    .offset(y: -2)
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
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.item]
        ) { result in
            guard let attachmentTargetChatID else { return }
            input.handleFileImport(result, for: attachmentTargetChatID)
            self.attachmentTargetChatID = nil
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotoItems,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: selectedPhotoItems) { _, newItems in
            guard !newItems.isEmpty, let attachmentTargetChatID else { return }
            Task {
                for item in newItems {
                    await input.handlePhotoPick(item, for: attachmentTargetChatID)
                }
            }
            selectedPhotoItems = []
            self.attachmentTargetChatID = nil
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
        .onChange(of: input.isSavingEdit) { oldValue, newValue in
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
