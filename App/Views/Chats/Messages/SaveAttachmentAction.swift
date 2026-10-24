import SwiftUI
import UniformTypeIdentifiers

/// Saves an attachment where the user can find it. macOS copies it straight
/// into Downloads. On iOS the app's Downloads folder sits inside its sandbox,
/// so the user picks a location in Files instead.
struct SaveAttachmentAction {
    let action: (Attachment) -> Void

    func callAsFunction(_ attachment: Attachment) {
        action(attachment)
    }
}

extension EnvironmentValues {
    @Entry var saveAttachment = SaveAttachmentAction { _ in }
}

extension View {
    /// Provides `saveAttachment` to the timeline rows. The save flow lives
    /// here rather than in the context menu, which dismisses on tap.
    func savesAttachments() -> some View {
        modifier(AttachmentSaver())
    }
}

private struct AttachmentSaver: ViewModifier {
    #if os(iOS)
    /// A named copy of the cached media for the Files picker to move.
    @State private var exportedFile: URL?
    @State private var isExporting = false
    #endif

    func body(content: Content) -> some View {
        content
            .environment(\.saveAttachment, SaveAttachmentAction { attachment in
                Task { await save(attachment) }
            })
            #if os(iOS)
            .fileMover(isPresented: $isExporting, file: exportedFile) { _ in
                discardExport()
            } onCancellation: {
                discardExport()
            }
            #endif
    }

    private func save(_ attachment: Attachment) async {
        guard let source = attachment.resolvedURL,
              let file = await MatrixMedia.localFile(for: source) else { return }
        // File copies clone on APFS instead of reading the media into memory.
        // Failures are silently ignored; the user can retry.
        #if os(macOS)
        try? FileManager.default.copyItem(at: file, to: uniqueDownloadsURL(named: attachment.suggestedFileName))
        #else
        discardExport()
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let copy = directory.appending(path: attachment.suggestedFileName)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: file, to: copy)
            exportedFile = copy
            isExporting = true
        } catch {
            try? FileManager.default.removeItem(at: directory)
        }
        #endif
    }

    #if os(iOS)
    /// Removes the copy's folder; after a successful move only the folder remains.
    private func discardExport() {
        guard let exportedFile else { return }
        try? FileManager.default.removeItem(at: exportedFile.deletingLastPathComponent())
        self.exportedFile = nil
    }
    #endif

    #if os(macOS)
    /// `name` in Downloads, numbered like Finder does when it's taken.
    private func uniqueDownloadsURL(named name: String) -> URL {
        let directory = URL.downloadsDirectory
        let baseURL = directory.appending(path: name)
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return baseURL }

        let stem = baseURL.deletingPathExtension().lastPathComponent
        let ext = baseURL.pathExtension
        var index = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            let candidate = directory.appending(path: candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
    #endif
}

private extension Attachment {
    /// The sender's file name, reduced to its last component so it can't point
    /// outside the destination folder, or a dated name with the type's extension.
    var suggestedFileName: String {
        if let fileName {
            let name = URL(filePath: fileName).lastPathComponent
            if !name.isEmpty, name != "/", name != "..", name != "." { return name }
        }
        let name = "relay-\(typeLabel)-\(Int(Date().timeIntervalSince1970))"
        guard let ext = mimeType.flatMap({ UTType(mimeType: $0)?.preferredFilenameExtension }) else { return name }
        return "\(name).\(ext)"
    }
}
