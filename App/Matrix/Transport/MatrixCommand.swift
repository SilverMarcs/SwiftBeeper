import Foundation

/// Adds the operation name to its typed arguments for the in-process C bridge.
nonisolated struct MatrixCommand<Arguments: Encodable>: Encodable {
    let action: String
    let arguments: Arguments

    private enum CodingKeys: String, CodingKey { case action }

    func encode(to encoder: any Encoder) throws {
        try arguments.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
    }
}
