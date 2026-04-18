import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MessageInputView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(MessageStore.self) private var messageStore
    @Environment(RealtimeCoordinator.self) private var coordinator

    @State private var draftMessagesByChatID: [String: String] = [:]
    @State private var showingFilePicker = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @FocusState private var isMessageFieldFocused: Bool

    private var cannotMessage: Bool {
        chatStore.selectedChat?.cannotMessage == true
    }

    private var selectedChat: Chat? {
        chatStore.selectedChat
    }

    private var selectedChatID: String? {
        selectedChat?.id
    }

    private var draftMessage: String {
        get {
            guard let selectedChatID else { return "" }
            return draftMessagesByChatID[selectedChatID] ?? ""
        }
        nonmutating set {
            guard let selectedChatID else { return }
            draftMessagesByChatID[selectedChatID] = newValue
        }
    }

    var body: some View {
        if cannotMessage {
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
                if let messagesError = messageStore.messagesError {
                    ComposerErrorBanner(message: messagesError)
                }

                if !messageStore.pendingAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(messageStore.pendingAttachments) { pending in
                                PendingAttachmentPreview(
                                    pending: pending,
                                    isSending: messageStore.isSendingMessage,
                                    onRemove: { messageStore.removePendingAttachment(id: pending.id) }
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

                    if hasActiveComposerAction {
                        Button {
                            withAnimation {
                                messageStore.cancelComposerAction()
                                if isEditing {
                                    draftMessage = ""
                                }
                            }
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
                        messageFieldPrompt,
                        text: Binding(
                            get: { draftMessage },
                            set: { draftMessage = $0 }
                        ),
                        axis: .vertical
                    )
                        .textFieldStyle(.plain)
                        .focused($isMessageFieldFocused)
                        .lineLimit(1 ... 7)
                        .padding(.horizontal, 4)
                        .padding(8)
                        .glassEffect(in: .rect(cornerRadius: 16))
                        .onSubmit {
                            handleSubmit()
                        }
                        .onChange(of: messageStore.editingMessage?.id) { _, newValue in
                            if let editingMessage = messageStore.editingMessage {
                                draftMessage = editingMessage.text ?? ""
                            } else if newValue == nil {
                                draftMessage = ""
                            }
                        }

                    Button {
                        handleSubmit()
                    } label: {
                        Group {
                            if messageStore.isSendingMessage {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: isEditing ? "checkmark" : "arrow.up")
                                    .font(.system(size: 15))
                                    .bold()
                            }
                        }
                    }
                    .opacity(sendButtonDisabled ? 0.35 : 0.85)
                    .controlSize(.large)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .allowsHitTesting(!sendButtonDisabled)
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
            handleFileImport(result)
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
                    await handlePhotoPick(item)
                }
            }
            selectedPhotoItems = []
        }
        #if os(macOS)
        .pasteHandler()
        #endif
        .onAppear {
            focusMessageField()
        }
        .onChange(of: chatStore.selectedChat?.id) { _, _ in
            focusMessageField()
        }
        .onChange(of: messageStore.activeComposerMessage?.id) { _, _ in
            focusMessageField()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("Focus", systemImage: "text.cursor") {
                    focusMessageField()
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(cannotMessage)

                Button("Edit Last", systemImage: "pencil") {
                    editMostRecentOutgoingMessage()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(mostRecentEditableOutgoingMessage == nil)
            }
        }
    }

    private var isEditing: Bool {
        messageStore.editingMessage != nil
    }

    private var hasActiveComposerAction: Bool {
        messageStore.activeComposerMessage != nil
    }

    private var messageFieldPrompt: String {
        if isEditing {
            return "Edit message"
        }
        if messageStore.replyingToMessage != nil {
            return "Reply message"
        }
        return "Message"
    }

    private var sendButtonDisabled: Bool {
        if messageStore.isSendingMessage { return true }
        if selectedChat == nil { return true }
        return trimmedDraftMessage.isEmpty && messageStore.pendingAttachments.isEmpty
    }

    private var trimmedDraftMessage: String {
        draftMessage.trimmed
    }

    private var mostRecentEditableOutgoingMessage: Message? {
        guard let selectedChat else { return nil }

        return messageStore.messages(for: selectedChat.id).last { message in
            messageStore.canEdit(message, in: selectedChat)
        }
    }

    private func handleSubmit() {
        if isEditing {
            saveEdit()
        } else {
            sendMessage()
        }
    }

    private func sendMessage() {
        guard let chatID = chatStore.selectedChat?.id else { return }
        let text = trimmedDraftMessage
        let attachments = messageStore.pendingAttachments

        guard !text.isEmpty || !attachments.isEmpty else { return }
        let previousDraft = draftMessage
        clearDraft(for: chatID)
        messageStore.clearPendingAttachments()

        Task {
            let didSend = await messageStore.sendMessage(text: text, attachments: attachments, to: chatID)
            if didSend {
                await coordinator.refreshAfterMessageMutation(chatID: chatID)
            } else {
                if (draftMessagesByChatID[chatID] ?? "").isEmpty {
                    draftMessagesByChatID[chatID] = previousDraft
                }
                if messageStore.pendingAttachments.isEmpty {
                    messageStore.pendingAttachments = attachments
                }
            }
        }
    }

    private func saveEdit() {
        let text = trimmedDraftMessage
        let editingChatID = messageStore.editingMessage?.chatID
        let previousDraft = draftMessage
        if let editingChatID {
            clearDraft(for: editingChatID)
        }

        Task {
            let didSave = await messageStore.saveEdit(newText: text)
            if didSave {
                if let chatID = chatStore.selectedChat?.id {
                    clearDraft(for: chatID)
                }
                if let chatID = chatStore.selectedChat?.id {
                    await coordinator.refreshAfterMessageMutation(chatID: chatID)
                }
            } else if
                let editingChatID,
                (draftMessagesByChatID[editingChatID] ?? "").isEmpty
            {
                draftMessagesByChatID[editingChatID] = previousDraft
            }
        }
    }

    private func clearDraft(for chatID: String) {
        draftMessagesByChatID[chatID] = nil
    }

    private func focusMessageField() {
        guard !cannotMessage else { return }
        Task { @MainActor in
            await Task.yield()
            isMessageFieldFocused = true
        }
    }

    private func editMostRecentOutgoingMessage() {
        guard let selectedChat, let message = mostRecentEditableOutgoingMessage else { return }
        withAnimation {
            messageStore.startEditing(message, in: selectedChat)
        }
        focusMessageField()
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let data = try? Data(contentsOf: url) else { return }
            let fileName = url.lastPathComponent
            let mimeType = url.mimeType

            messageStore.pendingAttachments.append(PendingAttachment(
                fileData: data,
                fileName: fileName,
                mimeType: mimeType
            ))
        case .failure:
            break
        }
    }

    private func handlePhotoPick(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }

        let mimeType: String
        let fileName: String

        if let contentType = item.supportedContentTypes.first {
            mimeType = contentType.preferredMIMEType ?? "application/octet-stream"
            let ext = contentType.preferredFilenameExtension ?? "bin"
            fileName = "photo.\(ext)"
        } else {
            mimeType = "image/jpeg"
            fileName = "photo.jpg"
        }

        messageStore.pendingAttachments.append(PendingAttachment(
            fileData: data,
            fileName: fileName,
            mimeType: mimeType
        ))
    }
}
