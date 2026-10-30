import RelayCore
import Foundation

/// The app's change stream from the core. The share extension doesn't use it.
extension MatrixRuntime {
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
}
