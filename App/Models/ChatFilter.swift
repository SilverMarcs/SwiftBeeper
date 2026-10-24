import Foundation

enum ChatFilter: Hashable, Identifiable {
    case inbox(InboxFilter)
    case service(serviceID: String, name: String)

    var id: String {
        switch self {
        case .inbox(let inbox): "inbox_\(inbox.rawValue)"
        case .service(let id, _): "service_\(id)"
        }
    }

    var label: String {
        switch self {
        case .inbox(let inbox): inbox.label
        case .service(_, let name): name
        }
    }

    var systemImage: String {
        switch self {
        case .inbox(let inbox): inbox.systemImage
        case .service(let serviceID, _): Self.systemImage(for: serviceID)
        }
    }

    var accountIDs: [String] {
        guard case .service(let serviceID, _) = self else { return [] }
        return [serviceID]
    }

    static func systemImage(for serviceID: String) -> String {
        let id = serviceID.lowercased()
        if id.contains("whatsapp") { return "phone.bubble.fill" }
        if id.contains("telegram") { return "paperplane.fill" }
        if id.contains("signal") { return "envelope.badge.shield.half.filled" }
        if id.contains("discord") { return "gamecontroller.fill" }
        if id.contains("slack") { return "square.grid.3x3.topleft.filled" }
        if id.contains("instagram") { return "camera.fill" }
        if id.contains("facebook") || id.contains("messenger") { return "bubble.left.and.bubble.right.fill" }
        if id.contains("linkedin") { return "person.text.rectangle.fill" }
        // Before the X check, which any ID containing an "x" (such as "matrix") matches.
        if id.contains("hungryserv") || id.contains("matrix") { return "circle.grid.hex.fill" }
        if id.contains("twitter") || id.contains("x") { return "x.squareroot" }
        if id.contains("gmessages") || id.contains("google messages") { return "message.fill" }
        return "bubble.left.and.bubble.right"
    }
}

enum InboxFilter: String, CaseIterable {
    case primary
    case archive
    case unread

    var label: String {
        switch self {
        case .primary: "Primary"
        case .archive: "Archive"
        case .unread: "Unread"
        }
    }

    var systemImage: String {
        switch self {
        case .primary: "tray.full"
        case .archive: "archivebox"
        case .unread: "envelope.badge"
        }
    }
}
