import Foundation

/// The decoded `entries` of a chat or message event.
struct EntriesPayload<Entry: Decodable>: Decodable {
    let entries: [Entry]?
}
