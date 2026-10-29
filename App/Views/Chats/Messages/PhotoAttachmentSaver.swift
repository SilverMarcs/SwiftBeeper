import SwiftUI

/// Keeps the Photos save task and its result outside the dismissing context menu.
struct PhotoAttachmentSaver: ViewModifier {
    @State private var isSaving = false
    @State private var isShowingResult = false
    @State private var saveError: String?

    func body(content: Content) -> some View {
        content
            .environment(\.saveAttachmentToPhotos, SaveAttachmentAction { attachment in
                Task { await save(attachment) }
            })
            .alert(saveError == nil ? "Saved to Photos" : "Couldn’t Save to Photos", isPresented: $isShowingResult) {
                Button("OK", role: .cancel) { }
            } message: {
                if let saveError {
                    Text(saveError)
                }
            }
    }

    private func save(_ attachment: Attachment) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await PhotoLibrarySaver.save(attachment)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
        isShowingResult = true
    }
}
