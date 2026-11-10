import Foundation

extension String {
    /// Whether formatted message Markdown links a Matrix user. The core
    /// canonicalizes every mention to a matrix.to URL.
    var hasMentionLinks: Bool {
        contains("matrix.to/#/@")
    }
}
