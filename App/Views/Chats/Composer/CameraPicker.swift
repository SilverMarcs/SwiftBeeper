#if os(iOS)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Uses the system capture and retake controls for both photos and videos.
struct CameraPicker: UIViewControllerRepresentable {
    let completion: @MainActor (Result<PendingAttachment?, Error>) -> Void

    func makeCoordinator() -> CameraPickerCoordinator {
        CameraPickerCoordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        let availableTypes = UIImagePickerController.availableMediaTypes(for: .camera) ?? []
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
            .filter { availableTypes.contains($0) }
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
}
#endif
