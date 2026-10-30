import Foundation

/// Where the Matrix core keeps its database and media cache. The store lives in
/// the app group so the share extension can open it whenever the app has it
/// closed.
nonisolated enum MatrixStore {
    /// macOS uses the team-prefixed form, which needs no provisioning profile
    /// entry; iOS requires the `group.` form.
    private static var appGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "RelayAppGroup") as? String
    }

    /// The store's directory, resolved once per process.
    static let directory = resolveDirectory()

    /// Whether the store holds a database. The share extension never creates
    /// one: an empty store would stop the app from moving in its old one.
    static var hasDatabase: Bool {
        FileManager.default.fileExists(atPath: database(in: directory).path)
    }

    /// Earlier builds kept the store in the app's own container.
    private static var legacyDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: "com.SilverMarcs.RelayEmbedded/matrix", directoryHint: .isDirectory)
    }

    private static func database(in directory: URL) -> URL {
        directory.appending(path: "data/gomuks.db")
    }

    /// The app group's store, after moving an earlier build's store into it.
    /// Falls back to the old location when that move fails, so a failed
    /// migration never looks like a sign-out.
    private static func resolveDirectory() -> URL {
        let fileManager = FileManager.default
        let legacy = legacyDirectory
        guard let appGroup, !appGroup.isEmpty,
              let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return legacy
        }
        let shared = container.appending(path: "matrix", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: database(in: legacy).path),
              !fileManager.fileExists(atPath: database(in: shared).path) else {
            return shared
        }
        do {
            // Without a database, anything here is a leftover such as a lock file.
            if fileManager.fileExists(atPath: shared.path) {
                try fileManager.removeItem(at: shared)
            }
            try fileManager.moveItem(at: legacy, to: shared)
            return shared
        } catch {
            return legacy
        }
    }
}
