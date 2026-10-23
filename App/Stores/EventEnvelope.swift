import Foundation

/// The fields every realtime event shares.
struct EventEnvelope: Decodable {
    let type: String
    let chatID: String?
    let entries: [[String: String]]?
    let seq: Int?

    enum CodingKeys: String, CodingKey {
        case type, chatID, entries, seq
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        chatID = try? container.decodeIfPresent(String.self, forKey: .chatID)
        seq = try? container.decodeIfPresent(Int.self, forKey: .seq)
        // Message events carry non-string values in entries; only receipt
        // events read this field, so fall back to nil on a type mismatch.
        entries = try? container.decodeIfPresent([[String: String]].self, forKey: .entries)
    }
}
