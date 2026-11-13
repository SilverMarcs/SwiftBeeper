import Foundation

extension APIClient {
    /// The homeserver's preview of a link, cached by the core. Nil when the
    /// page has nothing worth a card; throws when it's worth retrying later.
    static func linkPreview(url: String) async throws -> MessageLinkPreview? {
        struct Arguments: Encodable { let url: String }
        struct Output: Decodable { let preview: MessageLinkPreview? }
        let output: Output = try await execute("get-link-preview", arguments: Arguments(url: url))
        return output.preview
    }
}
