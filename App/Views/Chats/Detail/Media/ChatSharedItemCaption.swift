import Foundation

/// The secondary line under a shared file or link: who shared it and when,
/// and a file's size.
enum ChatSharedItemCaption {
    static func text(for message: Message, fileSize: Int? = nil) -> String {
        var parts: [String] = []
        if let fileSize {
            parts.append(Int64(fileSize).formatted(.byteCount(style: .file)))
        }
        parts.append(message.isSender ? String(localized: "You") : message.senderDisplayName)
        parts.append(message.timestamp.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }
}
