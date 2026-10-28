import Foundation

/// User links are identities, not guesses based on an @ prefix or display name.
struct MessageMentionLink {
    let userID: String

    init?(_ url: URL) {
        let encodedIdentifier: String
        switch url.scheme?.lowercased() {
        case "https", "http":
            guard url.host()?.lowercased() == "matrix.to",
                  let fragment = url.fragment(percentEncoded: true),
                  fragment.hasPrefix("/") else { return nil }
            encodedIdentifier = String(fragment.dropFirst().prefix(while: { $0 != "?" }))
        case "matrix":
            let path = url.path(percentEncoded: true)
            guard path.hasPrefix("u/") else { return nil }
            encodedIdentifier = "@" + path.dropFirst(2)
        default:
            return nil
        }
        guard !encodedIdentifier.contains("/"),
              let identifier = encodedIdentifier.removingPercentEncoding,
              identifier.hasPrefix("@"),
              let colon = identifier.firstIndex(of: ":"),
              colon > identifier.index(after: identifier.startIndex),
              identifier.index(after: colon) < identifier.endIndex else { return nil }
        userID = identifier
    }
}
