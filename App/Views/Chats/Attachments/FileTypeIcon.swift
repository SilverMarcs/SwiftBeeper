import SwiftUI
import UniformTypeIdentifiers

/// The system icon for the file's type on macOS, or a matching SF Symbol on
/// iOS, which has no file-type icon API.
struct FileTypeIcon: View {
    let type: UTType

    var body: some View {
        #if os(macOS)
        Image(nsImage: NSWorkspace.shared.icon(for: type))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 32, height: 32)
        #else
        Image(systemName: symbolName)
            .font(.title)
            .frame(width: 32, height: 32)
            .foregroundStyle(.secondary)
        #endif
    }

    #if !os(macOS)
    private var symbolName: String {
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "film" }
        if type.conforms(to: .audio) { return "music.note" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .archive) || type.conforms(to: .zip) { return "doc.zipper" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }
    #endif
}
