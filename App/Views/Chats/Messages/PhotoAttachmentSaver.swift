import SwiftUI

/// Keeps the Photos save task and its result outside the dismissing context menu.
struct PhotoAttachmentSaver: ViewModifier {
    @State private var isSaving = false
    @State private var isShowingResult = false
    @State private var saveError: String?

    func body(content: Content) -> some View {
        content
            .environment(\.saveAttachmentToPhotos, SaveAttachmentAction { attachments in
                Task { await save(attachments) }
            })
            .alert(saveError == nil ? "Saved to Photos" : "Couldn’t Save to Photos", isPresented: $isShowingResult) {
                Button("OK", role: .cancel) { }
            } message: {
                if let saveError {
                    Text(saveError)
                }
            }
    }

    private func save(_ attachments: [Attachment]) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            // One at a time, so the permission prompt appears only once.
            for attachment in attachments {
                try await PhotoLibrarySaver.save(attachment)
            }
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
        isShowingResult = true
    }
}
