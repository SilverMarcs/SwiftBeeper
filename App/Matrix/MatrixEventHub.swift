import Foundation
import Synchronization

/// Routes realtime payloads, which the core delivers on its own threads, to
/// each connection's stream. Payloads that arrive before the stream registers
/// are buffered, up to a limit.
nonisolated final class MatrixEventHub: Sendable {
    static let shared = MatrixEventHub()
    private struct State {
        var streams: [UInt: AsyncStream<Data>.Continuation] = [:]
        var pending: [UInt: [Data]] = [:]
        var closed: Set<UInt> = []
    }
    private let state = Mutex(State())

    func receive(_ data: Data, handle: UInt) {
        state.withLock { state in
            if state.closed.contains(handle) { return }
            if let continuation = state.streams[handle] { continuation.yield(data); return }
            if state.pending[handle, default: []].count < 32 { state.pending[handle, default: []].append(data) }
        }
    }

    func register(_ continuation: AsyncStream<Data>.Continuation, handle: UInt) {
        state.withLock { state in
            state.closed.remove(handle)
            state.streams[handle] = continuation
            for data in state.pending.removeValue(forKey: handle) ?? [] { continuation.yield(data) }
        }
    }

    func close(_ handle: UInt) {
        let continuation = state.withLock { state in
            state.closed.insert(handle)
            state.pending.removeValue(forKey: handle)
            return state.streams.removeValue(forKey: handle)
        }
        continuation?.finish()
    }
}
