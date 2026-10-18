import Foundation

enum MatrixFiles {
    nonisolated static let root = URL.applicationSupportDirectory
        .appending(path: "com.SilverMarcs.RelayEmbedded/matrix", directoryHint: .isDirectory)
    nonisolated static let host = "relay.local.invalid"
    nonisolated static let baseURL: URL = {
        guard let url = URL(string: "https://relay.local.invalid") else {
            preconditionFailure("Invalid local transport identifier")
        }
        return url
    }()

    nonisolated static func configuration() throws -> MatrixConfiguration {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let path = root.appending(path: "native-config.private.json")
        if FileManager.default.fileExists(atPath: path.path) {
            let saved = try JSONDecoder().decode(MatrixConfiguration.self, from: Data(contentsOf: path))
            // iOS can relocate the data container when installing an update.
            // The profile moves with it; its old absolute path is no longer valid.
            guard saved.stateDir != root.path else { return saved }
            let current = MatrixConfiguration(stateDir: root.path, accessToken: saved.accessToken,
                                               manageSecret: saved.manageSecret,
                                               beeperHomeserverUrl: saved.beeperHomeserverUrl)
            try JSONEncoder().encode(current).write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            return current
        }
        let secret = UUID().uuidString + UUID().uuidString
        let config = MatrixConfiguration(stateDir: root.path, accessToken: secret, manageSecret: secret,
                                           beeperHomeserverUrl: "https://matrix.beeper.com")
        try JSONEncoder().encode(config).write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        return config
    }
}
