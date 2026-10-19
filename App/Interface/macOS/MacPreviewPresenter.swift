#if os(macOS)
import AppKit
import QuickLookUI

/// Quick Look has one system panel; keep its data source alive independently
/// of a particular conversation or participant window.
@MainActor
final class MacPreviewPresenter: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = MacPreviewPresenter()
    private var url: URL?
    private var task: Task<Void, Never>?

    func show(_ attachment: Attachment, onError: @escaping (Error) -> Void) {
        task?.cancel()
        task = Task {
            do {
                let file = try await AttachmentFiles.load(attachment)
                guard !Task.isCancelled else { return }; show(file)
            } catch { onError(error) }
        }
    }
    func showImage(_ source: String) {
        task?.cancel()
        task = Task {
            guard let file = await AuthenticatedImageLoader.downloadToTempFile(urlString: source, fileExtension: "jpg"), !Task.isCancelled else { return }
            show(file)
        }
    }
    private func show(_ file: URL) {
        url = file
        let panel = QLPreviewPanel.shared(); panel?.dataSource = self; panel?.delegate = self
        panel?.reloadData(); panel?.makeKeyAndOrderFront(nil)
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { url as NSURL? }
}
#endif
