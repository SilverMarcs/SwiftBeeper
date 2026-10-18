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

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try start()
        guard let url = request.url, url.host == MatrixFiles.host else { throw MatrixError.invalidRequest }
        let config = try MatrixFiles.configuration()
        let envelope = MatrixRequest(method: request.httpMethod ?? "GET", url: url.absoluteString,
                                       headers: ["Authorization": ["Bearer " + config.accessToken],
                                                 "X-RelayCore-Manage-Secret": [config.manageSecret],
                                                 "Content-Type": [request.value(forHTTPHeaderField: "Content-Type") ?? "application/json"]],
                                       bodyBase64: request.httpBody?.base64EncodedString())
        let input = try JSONEncoder().encode(envelope)
        let nativeHandle = handle
        // The Go core and SQLite pool support concurrent requests. Blocking FFI
        // calls use the cooperative pool off both the UI and lifecycle actor.
        let raw = try await Task.detached(priority: .userInitiated) {
            guard let result = String(decoding: input, as: UTF8.self).withCString({
                RelayCoreHandleRequest(nativeHandle, UnsafeMutablePointer(mutating: $0))
            }) else { throw MatrixError.invalidResponse }
            defer { RelayCoreFreeCString(result) }
            return Data(String(cString: result).utf8)
        }.value
        let result = try JSONDecoder().decode(MatrixResponse.self, from: raw)
        guard let body = result.response,
              let response = HTTPURLResponse(url: url, statusCode: body.status, httpVersion: "HTTP/1.1",
                                             headerFields: body.headers?.mapValues { $0.joined(separator: ", ") }) else {
            throw MatrixError.invalidResponse
        }
        return (Data(base64Encoded: body.bodyBase64 ?? "") ?? Data(), response)
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
            if (try? JSONDecoder().decode(MatrixCommandFailure.self, from: output))?.error != nil {
                throw MatrixError.operationFailed
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

    func sendRealtime(_ data: Data, connection: UInt) throws {
        guard handle != 0 else { throw MatrixError.cannotStart }
        let result = String(decoding: data, as: UTF8.self).withCString {
            RelayCoreRealtimeSend(handle, connection, UnsafeMutablePointer(mutating: $0))
        }
        if let result { RelayCoreFreeCString(result); throw MatrixError.operationFailed }
    }

    func closeRealtime(_ connection: UInt) {
        MatrixEventHub.shared.close(connection)
        if handle != 0 { RelayCoreRealtimeClose(handle, connection) }
    }
}
