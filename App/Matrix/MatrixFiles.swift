import Foundation

enum MatrixFiles {
    nonisolated static let root = URL.applicationSupportDirectory
        .appending(path: "com.SilverMarcs.RelayEmbedded/matrix", directoryHint: .isDirectory)
    nonisolated static let host = "relay.local.invalid"
    nonisolated static let assetURL: URL = {
        guard let url = URL(string: "https://relay.local.invalid/media") else {
            preconditionFailure("Invalid local transport identifier")
        }
        return url
    }()

    nonisolated static func configuration() throws -> MatrixConfiguration {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        return MatrixConfiguration(stateDir: root.path)
    }
}
