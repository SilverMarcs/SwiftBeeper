import SwiftUI
import PhotosUI
#if os(iOS)
import AVFoundation
import UIKit
#endif

/// The "+" menu that adds photos or files to the composer. Picks attach to the
/// composer the menu belongs to, even if a picker finishes after navigating away.
struct AttachmentMenu<MenuLabel: View>: View {
    @Environment(InputManager.self) private var input

    let composer: Composer
    @ViewBuilder let label: MenuLabel

    @State private var showingFilePicker = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    #if os(iOS)
    @State private var showingCamera = false
    @State private var cameraError: String?
    #endif

    var body: some View {
        Menu {
            Button("Photos Library", systemImage: "photo.on.rectangle.angled") {
                showingPhotoPicker = true
            }

            #if os(iOS)
            Button("Camera", systemImage: "camera", action: openCamera)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            #endif

            Divider()

            Button("Attach Files", systemImage: "paperclip") {
                showingFilePicker = true
            }
        } label: {
            label
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { result in
                showingCamera = false
                switch result {
                case .success(let attachment):
                    if let attachment {
                        input.addAttachment(
                            data: attachment.fileData,
                            fileName: attachment.fileName,
                            mimeType: attachment.mimeType,
                            to: composer
                        )
                    }
                case .failure:
                    cameraError = "The capture couldn’t be attached. Please try again."
                }
            }
            .ignoresSafeArea()
        }
        .alert("Camera", isPresented: Binding(
            get: { cameraError != nil },
            set: { if !$0 { cameraError = nil } }
        )) {
            Button("OK", role: .cancel) { cameraError = nil }
        } message: {
            Text(cameraError ?? "")
        }
        #endif
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotoItems,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: selectedPhotoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { [composer] in
                for item in newItems {
                    await input.handlePhotoPick(item, for: composer)
                }
            }
            selectedPhotoItems = []
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.item]
        ) { result in
            input.handleFileImport(result, for: composer)
        }
    }

    #if os(iOS)
    private func openCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            cameraError = "Allow camera access for Relay in Settings to take photos and videos."
        default:
            showingCamera = true
        }
    }
    #endif
}
