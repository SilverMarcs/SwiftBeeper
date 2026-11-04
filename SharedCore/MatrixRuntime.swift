import RelayCore
import Foundation
import Darwin

/// Owns the in-process Matrix core. Commands are JSON objects naming an
/// `action`; the core answers with JSON, or `{"error": …}` on failure.
///
/// The app and its share extension open the same store, one process at a time,
/// under an exclusive file lock. The store opens on the first command and can
/// close again so the other process can take it: while the iOS app is in the
/// background, and while a share is underway.
///
/// `share.lock` decides which process may open the store. The share extension
/// holds it from before it asks for the store until after it hands it back.
/// While it's held only the extension may open the store; otherwise only the app.
actor MatrixRuntime {
    static let shared = MatrixRuntime()
    /// The core's database and media cache, plus uploads staged for it.
    private static let directory = MatrixStore.directory
    private static let isShareExtension = Bundle.main.bundleURL.pathExtension == "appex"
    /// The core's handle, which outlives closing and reopening the store.
    private(set) var handle: UInt = 0
    private(set) var isOpen = false
    private var lockFile: Int32 = -1
    /// The share extension's hold on `share.lock` while a share is underway.
    private var shareLockFile: Int32 = -1
    private var keepsOpen = true
    /// Closes the store once, as soon as commands still running finish.
    private var closesWhenIdle = false
    private var runningCommands = 0
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []
    /// What the app last asked for, reapplied whenever the store reopens.
    private var isActive = false
    private var openedRoomID = ""

    func start() throws {
        guard !isOpen else { return }
        if Self.isShareExtension {
            guard shareLockFile >= 0 else { throw MatrixError.storeInUse }
        } else {
            guard !Self.isShareUnderway else { throw MatrixError.storeInUse }
        }
        umask(0o077)
        try Self.createPrivateDirectory(Self.directory)
        lockFile = Darwin.open(Self.directory.appending(path: "runtime.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFile >= 0, flock(lockFile, LOCK_EX | LOCK_NB) == 0 else {
            releaseLock()
            throw MatrixError.storeInUse
        }
        do {
            if handle == 0 {
                let configuration = try JSONEncoder().encode(CoreConfiguration(
                    stateDir: Self.directory.path,
                    memoryLimitMB: Bundle.main.object(forInfoDictionaryKey: "RelayCoreMemoryLimitMB") as? Int ?? 0
                ))
                handle = withJSONCString(configuration) { RelayCoreCreate($0) }
                guard handle != 0 else { throw MatrixError.cannotStart }
            }
            guard RelayCoreStart(handle) == 0 else { throw MatrixError.cannotStart }
        } catch {
            releaseLock()
            throw error
        }
        isOpen = true
        closesWhenIdle = false
        if isActive { run("active", ["active": true]) }
        if !openedRoomID.isEmpty { run("opened-room", ["roomID": openedRoomID]) }
    }

    /// Runs an encoded `MatrixCommand` off the actor and returns the core's result.
    func command(_ data: Data) async throws -> Data {
        try start()
        runningCommands += 1
        defer {
            runningCommands -= 1
            closeIfIdle()
        }
        let nativeHandle = handle
        return try await Task.detached(priority: .userInitiated) {
            guard let result = withJSONCString(data, { RelayCoreCommand(nativeHandle, $0) }) else {
                throw MatrixError.invalidResponse
            }
            defer { RelayCoreFreeCString(result) }
            let output = Data(String(cString: result).utf8)
            if let message = (try? JSONDecoder().decode(MatrixCommandFailure.self, from: output))?.error {
                throw MatrixError.core(message)
            }
            return output
        }.value
    }

    /// The core syncs eagerly only while active.
    func setActive(_ active: Bool) async {
        isActive = active
        // A closed store has no sync to pause.
        guard active || isOpen else { return }
        _ = try? await command("active", ["active": active])
    }

    /// Tells the core which room is on screen, or none.
    func openedRoom(_ roomID: String?) async {
        openedRoomID = roomID ?? ""
        // Opening the store applies it.
        guard isOpen else { return }
        _ = try? await command("opened-room", ["roomID": openedRoomID])
    }

    /// Whether the store stays open between commands. The iOS app closes it in
    /// the background, where an open database in the app group gets the app
    /// terminated, and where the share extension may want it.
    func setKeepsOpen(_ keepsOpen: Bool) {
        self.keepsOpen = keepsOpen
        closeIfIdle()
    }

    /// Returns once the store is closed, after commands still running finish.
    func waitUntilClosed() async {
        guard isOpen else { return }
        await withCheckedContinuation { closeWaiters.append($0) }
    }

    /// Closes the store for the other process once commands still running
    /// finish. The share lock keeps it closed for as long as that matters.
    func closeWhenIdle() {
        closesWhenIdle = true
        closeIfIdle()
    }

    /// Marks a share as underway, from before the share extension asks for the
    /// store until after it hands it back. Returns false while another share
    /// extension process has one underway. The system drops the lock if the
    /// extension dies, and the extension ends it before it can be suspended.
    func beginShare() throws -> Bool {
        guard shareLockFile < 0 else { return true }
        umask(0o077)
        try Self.createPrivateDirectory(Self.directory)
        let file = Darwin.open(Self.shareLockPath, O_CREAT | O_RDWR, 0o600)
        guard file >= 0 else { throw MatrixError.cannotStart }
        guard flock(file, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(file)
            return false
        }
        shareLockFile = file
        return true
    }

    func endShare() {
        guard shareLockFile >= 0 else { return }
        Darwin.close(shareLockFile)
        shareLockFile = -1
    }

    /// Whether a share extension has a share underway.
    nonisolated static var isShareUnderway: Bool {
        let file = Darwin.open(shareLockPath, O_RDONLY)
        guard file >= 0 else { return false }
        defer { Darwin.close(file) }
        guard flock(file, LOCK_SH | LOCK_NB) == 0 else { return errno == EWOULDBLOCK }
        flock(file, LOCK_UN)
        return false
    }

    private nonisolated static var shareLockPath: String {
        directory.appending(path: "share.lock").path
    }

    /// Closes the store now, so the other process can open it.
    func close() {
        guard isOpen else { return }
        RelayCoreStop(handle)
        isOpen = false
        releaseLock()
        for waiter in closeWaiters { waiter.resume() }
        closeWaiters = []
    }

    /// The core's cached file for Matrix media.
    func localAsset(_ source: String) async throws -> URL {
        let response = try await command("local-asset", ["url": source])
        return URL(filePath: try JSONDecoder().decode(MatrixLocalAsset.self, from: response).path)
    }

    /// Hands upload bytes to the core through a private file it reads before
    /// this returns.
    func stageUpload(_ data: Data, fileName: String, mimeType: String) async throws -> Data {
        try start()
        let directory = Self.directory.appending(path: "incoming", directoryHint: .isDirectory)
        try Self.createPrivateDirectory(directory)
        let path = directory.appending(path: UUID().uuidString)
        try data.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        defer { try? FileManager.default.removeItem(at: path) }
        return try await command("stage-upload", ["path": path.path, "fileName": fileName, "mimeType": mimeType])
    }

    private func command(_ action: String, _ arguments: [String: some Encodable]) async throws -> Data {
        try await command(JSONEncoder().encode(MatrixCommand(action: action, arguments: arguments)))
    }

    /// Runs a quick command on the actor, ignoring its result.
    private func run(_ action: String, _ arguments: [String: some Encodable]) {
        guard let data = try? JSONEncoder().encode(MatrixCommand(action: action, arguments: arguments)),
              let result = withJSONCString(data, { RelayCoreCommand(handle, $0) }) else { return }
        RelayCoreFreeCString(result)
    }

    private func closeIfIdle() {
        guard runningCommands == 0, !keepsOpen || closesWhenIdle else { return }
        close()
    }

    private func releaseLock() {
        guard lockFile >= 0 else { return }
        Darwin.close(lockFile)
        lockFile = -1
    }

    private static func createPrivateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }
}

/// An action name merged into its encoded arguments, as the core expects.
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

/// Arguments for actions that take none.
nonisolated struct EmptyArguments: Encodable {}

private nonisolated struct CoreConfiguration: Encodable {
    let stateDir: String
    /// Caps the core's heap in memory-limited app extensions; zero leaves it unset.
    let memoryLimitMB: Int
}

/// The error the core reports in place of a command's result.
private nonisolated struct MatrixCommandFailure: Decodable { let error: String? }

private nonisolated struct MatrixLocalAsset: Decodable { let path: String }

/// Passes JSON to a core entry point, which reads it only during the call.
nonisolated func withJSONCString<Result>(_ json: Data, _ body: (UnsafeMutablePointer<CChar>) -> Result) -> Result {
    String(decoding: json, as: UTF8.self).withCString { body(UnsafeMutablePointer(mutating: $0)) }
}
