import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
struct PasteHandler: ViewModifier {
    @Environment(InputManager.self) private var input
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

        var didProcess = false
        for item in items {
            if !Set(item.types).intersection(mediaTypes).isEmpty {
                processPasteItem(item)
                didProcess = true
            }
        }

        return didProcess
    }

    private func processPasteItem(_ item: NSPasteboardItem) {
        guard let targetChatID = input.selectedChatID else { return }

        if let fileURLData = item.data(forType: .fileURL),
           let fileURL = URL(dataRepresentation: fileURLData, relativeTo: nil) {
            guard let data = try? Data(contentsOf: fileURL) else { return }
            let fileName = fileURL.lastPathComponent
            let mimeType = fileURL.mimeType
            input.addAttachment(data: data, fileName: fileName, mimeType: mimeType, to: targetChatID)
        } else if let imageData = item.data(forType: .png) {
            input.addAttachment(
                data: imageData,
                fileName: "Pasted_Image_\(UUID().uuidString.prefix(8)).png",
                mimeType: "image/png",
                to: targetChatID
            )
        } else if let imageData = item.data(forType: .tiff) {
            input.addAttachment(
                data: imageData,
                fileName: "Pasted_Image_\(UUID().uuidString.prefix(8)).tiff",
                mimeType: "image/tiff",
                to: targetChatID
            )
        }
    }

}

private struct HostingViewFinder: NSViewRepresentable {
    @Binding var hostingView: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            await Task.yield()
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
