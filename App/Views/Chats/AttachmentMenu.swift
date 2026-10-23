import SwiftUI
import PhotosUI

/// The "+" menu that adds photos or files to the composer. Picks attach to the
/// chat that was open when the menu was used, even if a picker finishes later.
struct AttachmentMenu<MenuLabel: View>: View {
    @Environment(InputManager.self) private var input

    @ViewBuilder let label: MenuLabel

    @State private var showingFilePicker = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var attachmentTargetChatID: String?

    var body: some View {
        Menu {
            Button("Photos Library", systemImage: "photo.on.rectangle.angled") {
                attachmentTargetChatID = input.selectedChatID
                showingPhotoPicker = true
            }

            Button("Attach Files", systemImage: "paperclip") {
                attachmentTargetChatID = input.selectedChatID
                showingFilePicker = true
            }
        } label: {
            label
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
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.item]
        ) { result in
            guard let attachmentTargetChatID else { return }
            input.handleFileImport(result, for: attachmentTargetChatID)
            self.attachmentTargetChatID = nil
        }
    }
}
