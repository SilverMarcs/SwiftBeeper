#if !os(macOS)
import SwiftUI
import PhotosUI

/// The "+" attachment menu shown in the iPhone chat detail's bottom toolbar,
/// alongside the `.searchable` text input. Drives the shared `InputManager`.
struct MessageInputMenu: View {
    @Environment(InputManager.self) private var input

    @State private var showingFilePicker = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    var body: some View {
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
            Image(systemName: "plus")
        }
        .menuIndicator(.hidden)
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
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.item]
        ) { result in
            input.handleFileImport(result)
        }
    }
}
#endif
