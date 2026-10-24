#if os(macOS)
import SwiftUI

/// Intercepts ⌘V in the composer's window and turns pasted files and images
/// into pending attachments. Text pastes fall through to the text field.
struct PasteHandler: ViewModifier {
    @Environment(InputManager.self) private var input
    @State private var eventMonitor: Any?
    @State private var hostingView: NSView?

    /// Image types pasted as data, with their file extension and MIME type.
    private static let imageTypes: [(type: NSPasteboard.PasteboardType, fileExtension: String, mimeType: String)] = [
        (.png, "png", "image/png"),
        (.tiff, "tiff", "image/tiff")
    ]

    func body(content: Content) -> some View {
        content
            .onAppear {
                eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let isPaste = event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v"
                    return isPaste && isKeyWindow() && handlePaste() ? nil : event
                }
            }
            .onDisappear {
                if let eventMonitor {
                    NSEvent.removeMonitor(eventMonitor)
                }
            }
            .background(HostingViewFinder(hostingView: $hostingView))
    }

    /// The monitor is app-wide; only the composer's own window should react.
    private func isKeyWindow() -> Bool {
        guard let window = hostingView?.window else { return false }
        return window == NSApp.keyWindow
    }

    /// Returns whether the pasteboard held any files or images.
    private func handlePaste() -> Bool {
        let mediaTypes: Set<NSPasteboard.PasteboardType> = [.fileURL, .png, .tiff]
        let items = (NSPasteboard.general.pasteboardItems ?? []).filter { item in
            item.types.contains(where: mediaTypes.contains)
        }
        items.forEach(addAttachment)
        return !items.isEmpty
    }

    private func addAttachment(from item: NSPasteboardItem) {
        guard let chatID = input.selectedChatID else { return }

        if let fileURLData = item.data(forType: .fileURL),
           let fileURL = URL(dataRepresentation: fileURLData, relativeTo: nil) {
            guard let data = try? Data(contentsOf: fileURL) else { return }
            input.addAttachment(data: data, fileName: fileURL.lastPathComponent, mimeType: fileURL.mimeType, to: chatID)
            return
        }
        for imageType in Self.imageTypes {
            guard let data = item.data(forType: imageType.type) else { continue }
            input.addAttachment(
                data: data,
                fileName: "Pasted_Image_\(UUID().uuidString.prefix(8)).\(imageType.fileExtension)",
                mimeType: imageType.mimeType,
                to: chatID
            )
            return
        }
    }
}

/// Captures a view in the modifier's window, so the paste monitor can check
/// which window is key.
private struct HostingViewFinder: NSViewRepresentable {
    @Binding var hostingView: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Publishing the binding during view creation would modify state mid-update.
        Task {
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
