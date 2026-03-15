import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
struct PasteHandler: ViewModifier {
    @Environment(MessageStore.self) private var messageStore
    @State private var eventMonitor: Any?
    @State private var hostingView: NSView?

    func body(content: Content) -> some View {
        content
            .onAppear {
                eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
                        if isKeyWindow(), handlePaste() {
                            return nil
                        }
                    }
                    return event
                }
            }
            .onDisappear {
                if let monitor = eventMonitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
            .background(HostingViewFinder(hostingView: $hostingView))
    }

    private func isKeyWindow() -> Bool {
        guard let hostingView, let viewWindow = hostingView.window else { return false }
        return viewWindow == NSApp.keyWindow
    }

    private func handlePaste() -> Bool {
        guard let items = NSPasteboard.general.pasteboardItems else { return false }

        let mediaTypes: Set<NSPasteboard.PasteboardType> = [.fileURL, .png, .tiff]

        for item in items {
            if !Set(item.types).intersection(mediaTypes).isEmpty {
                processPasteItem(item)
                return true
            }
        }

        return false
    }

    private func processPasteItem(_ item: NSPasteboardItem) {
        if let fileURLData = item.data(forType: .fileURL),
           let fileURL = URL(dataRepresentation: fileURLData, relativeTo: nil) {
            guard let data = try? Data(contentsOf: fileURL) else { return }
            let fileName = fileURL.lastPathComponent
            let mimeType = fileURL.mimeType
            messageStore.pendingAttachment = PendingAttachment(
                fileData: data,
                fileName: fileName,
                mimeType: mimeType
            )
        } else if let imageData = item.data(forType: .png) {
            messageStore.pendingAttachment = PendingAttachment(
                fileData: imageData,
                fileName: "Pasted_Image_\(UUID().uuidString.prefix(8)).png",
                mimeType: "image/png"
            )
        } else if let imageData = item.data(forType: .tiff) {
            messageStore.pendingAttachment = PendingAttachment(
                fileData: imageData,
                fileName: "Pasted_Image_\(UUID().uuidString.prefix(8)).tiff",
                mimeType: "image/tiff"
            )
        }
    }

}

private struct HostingViewFinder: NSViewRepresentable {
    @Binding var hostingView: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            hostingView = view
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func pasteHandler() -> some View {
        modifier(PasteHandler())
    }
}
#endif
