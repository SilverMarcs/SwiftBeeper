import RelayCore
import Foundation
import Darwin

actor MatrixRuntime {
    static let shared = MatrixRuntime()
    private var handle: UInt = 0
    private var lockFile: Int32 = -1

    func start() throws {
        guard handle == 0 else { return }
        umask(0o077)
        let config = try MatrixFiles.configuration()
        lockFile = Darwin.open(MatrixFiles.root.appending(path: "runtime.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFile >= 0, flock(lockFile, LOCK_EX | LOCK_NB) == 0 else {
            if lockFile >= 0 { Darwin.close(lockFile); lockFile = -1 }
            throw MatrixError.storeInUse
        }
        do {
            let data = try JSONEncoder().encode(config)
            handle = String(decoding: data, as: UTF8.self).withCString {
                RelayCoreCreate(UnsafeMutablePointer(mutating: $0))
            }
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

    func command(_ data: Data) async throws -> Data {
        try start()
        let nativeHandle = handle
        return try await Task.detached(priority: .userInitiated) {
            guard let result = String(decoding: data, as: UTF8.self).withCString({
                RelayCoreCommand(nativeHandle, UnsafeMutablePointer(mutating: $0))
            }) else { throw MatrixError.invalidResponse }
            defer { RelayCoreFreeCString(result) }
            let output = Data(String(cString: result).utf8)
            if let message = (try? JSONDecoder().decode(MatrixCommandFailure.self, from: output))?.error {
                throw APIError.operation(message)
            }
            return output
        }.value
    }

    func setActive(_ active: Bool) async {
        let data = Data((active ? "{\"action\":\"active\",\"active\":true}" : "{\"action\":\"active\",\"active\":false}").utf8)
        _ = try? await command(data)
    }

    func openedRoom(_ roomID: String?) async {
        guard let data = try? JSONEncoder().encode(MatrixRoomCommand(roomID: roomID ?? "")) else { return }
        _ = try? await command(data)
    }

    func localAsset(_ source: String) async throws -> URL {
        let data = try JSONEncoder().encode(MatrixAssetCommand(url: source))
        let response = try await command(data)
        let result = try JSONDecoder().decode(MatrixLocalAsset.self, from: response)
        return URL(filePath: result.path)
    }

    func stageUpload(_ data: Data, fileName: String, mimeType: String) async throws -> Data {
        try start()
        let directory = MatrixFiles.root.appending(path: "incoming", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let path = directory.appending(path: UUID().uuidString)
        try data.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        defer { try? FileManager.default.removeItem(at: path) }
        let command = try JSONEncoder().encode(MatrixUploadCommand(path: path.path, fileName: fileName, mimeType: mimeType))
        return try await self.command(command)
    }

    func events() throws -> (UInt, AsyncStream<Data>) {
        try start()
        let channel = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(256))
        let connection = RelayCoreRealtimeConnect(handle) { connection, payload in
            guard let payload else { return }
            MatrixEventHub.shared.receive(Data(String(cString: payload).utf8), handle: connection)
        }
        guard connection != 0 else { throw MatrixError.operationFailed }
        MatrixEventHub.shared.register(channel.continuation, handle: connection)
        return (connection, channel.stream)
    }

    func setRealtimeSubscriptions(messageChatIDs: [String], connection: UInt) throws {
        guard handle != 0 else { throw MatrixError.cannotStart }
        let data = try JSONEncoder().encode(messageChatIDs)
        let result = String(decoding: data, as: UTF8.self).withCString {
            RelayCoreRealtimeSubscribe(handle, connection, UnsafeMutablePointer(mutating: $0))
        }
        if let result { RelayCoreFreeCString(result); throw MatrixError.operationFailed }
    }

    func closeRealtime(_ connection: UInt) {
        MatrixEventHub.shared.close(connection)
        if handle != 0 { RelayCoreRealtimeClose(handle, connection) }
    }
}
