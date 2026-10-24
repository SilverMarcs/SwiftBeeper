import RelayCore
import Foundation
import Darwin

/// Owns the in-process Matrix core. Commands are JSON objects naming an
/// `action`; the core answers with JSON, or `{"error": …}` on failure.
/// Realtime events arrive through `MatrixEventHub`.
actor MatrixRuntime {
    static let shared = MatrixRuntime()
    /// The core's database and media cache, plus uploads staged for it.
    private static let directory = URL.applicationSupportDirectory
        .appending(path: "com.SilverMarcs.RelayEmbedded/matrix", directoryHint: .isDirectory)
    private var handle: UInt = 0
    private var lockFile: Int32 = -1

    func start() throws {
        guard handle == 0 else { return }
        umask(0o077)
        try Self.createPrivateDirectory(Self.directory)
        lockFile = Darwin.open(Self.directory.appending(path: "runtime.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFile >= 0, flock(lockFile, LOCK_EX | LOCK_NB) == 0 else {
            if lockFile >= 0 { Darwin.close(lockFile); lockFile = -1 }
            throw MatrixError.storeInUse
        }
        do {
            let configuration = try JSONEncoder().encode(["stateDir": Self.directory.path])
            handle = withJSONCString(configuration) { RelayCoreCreate($0) }
            guard handle != 0 else { throw MatrixError.cannotStart }
            guard RelayCoreStart(handle) == 0 else {
                RelayCoreDestroy(handle)
                handle = 0
                throw MatrixError.cannotStart
            }
        } catch {
            Darwin.close(lockFile); lockFile = -1
            throw error
        }
    }

    /// Runs an encoded `MatrixCommand` off the actor and returns the core's result.
    func command(_ data: Data) async throws -> Data {
        try start()
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
        _ = try? await command("active", ["active": active])
    }

    /// Tells the core which room is on screen, or none.
    func openedRoom(_ roomID: String?) async {
        _ = try? await command("opened-room", ["roomID": roomID ?? ""])
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

    func events() throws -> (UInt, AsyncStream<Data>) {
        try start()
        let channel = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(256))
        let connection = RelayCoreRealtimeConnect(handle) { connection, payload, length in
            // The bytes are valid only during this call, so copy them once.
            guard let payload, length > 0 else { return }
            MatrixEventHub.shared.receive(Data(bytes: payload, count: length), handle: connection)
        }
        guard connection != 0 else { throw MatrixError.operationFailed }
        MatrixEventHub.shared.register(channel.continuation, handle: connection)
        return (connection, channel.stream)
    }

    func setRealtimeSubscriptions(messageChatIDs: [String], connection: UInt) throws {
        guard handle != 0 else { throw MatrixError.cannotStart }
        let data = try JSONEncoder().encode(messageChatIDs)
        let result = withJSONCString(data) { RelayCoreRealtimeSubscribe(handle, connection, $0) }
        if let result { RelayCoreFreeCString(result); throw MatrixError.operationFailed }
    }

    func closeRealtime(_ connection: UInt) {
        MatrixEventHub.shared.close(connection)
        if handle != 0 { RelayCoreRealtimeClose(handle, connection) }
    }

    private func command(_ action: String, _ arguments: [String: some Encodable]) async throws -> Data {
        try await command(JSONEncoder().encode(MatrixCommand(action: action, arguments: arguments)))
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

/// The error the core reports in place of a command's result.
private nonisolated struct MatrixCommandFailure: Decodable { let error: String? }

private nonisolated struct MatrixLocalAsset: Decodable { let path: String }

/// Passes JSON to a core entry point, which reads it only during the call.
private nonisolated func withJSONCString<Result>(_ json: Data, _ body: (UnsafeMutablePointer<CChar>) -> Result) -> Result {
    String(decoding: json, as: UTF8.self).withCString { body(UnsafeMutablePointer(mutating: $0)) }
}
