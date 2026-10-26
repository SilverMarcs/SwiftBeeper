#if os(iOS)
import UIKit
import UniformTypeIdentifiers

@MainActor
final class CameraPickerCoordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let completion: @MainActor (Result<PendingAttachment?, Error>) -> Void

    init(completion: @escaping @MainActor (Result<PendingAttachment?, Error>) -> Void) {
        self.completion = completion
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        completion(.success(nil))
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        if let url = info[.mediaURL] as? URL {
            // Read the temporary movie before dismissing the picker. Keep file IO
            // off the main actor so larger videos don't block the interface.
            Task {
                let result = await Task.detached {
                    Result<PendingAttachment?, Error> {
                        let data = try Data(contentsOf: url)
                        let type = UTType(filenameExtension: url.pathExtension)
                        return PendingAttachment(
                            fileData: data,
                            fileName: "video.\(url.pathExtension)",
                            mimeType: type?.preferredMIMEType ?? "video/quicktime"
                        )
                    }
                }.value
                completion(result)
            }
        } else if let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.9) {
            completion(.success(PendingAttachment(
                fileData: data,
                fileName: "photo.jpg",
                mimeType: "image/jpeg"
            )))
        } else {
            completion(.failure(CocoaError(.fileReadCorruptFile)))
        }
    }
}
#endif
