import Foundation
import OSLog

/// Remembers messages shown in an open chat and reports them to the push
/// server. This is independent of Matrix read state and sends no read receipts.
@MainActor
final class SeenMessages {
    // Match the server's delivery retention, measuring from observation rather
    // than the original network timestamp of a delayed bridged message.
    private static let window: TimeInterval = 24 * 60 * 60
    private static let capacity = 2_000
    private static let batchSize = 200
    private static let storageKey = "push.seenMessages"
    private let logger = Logger(subsystem: "com.SilverMarcs.Relay", category: "seen-messages")
    private var records: [String: SeenMessageRecord]
    private var uploadTask: Task<Void, Never>?
    private var generation = UUID()

    init() {
        records = UserDefaults.standard.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: SeenMessageRecord].self, from: $0) } ?? [:]
        prune()
    }

    func contains(_ messageID: String) -> Bool {
        guard let record = records[messageID] else { return false }
        return record.seenAt > Date.now.addingTimeInterval(-Self.window)
    }

    func insert(_ messages: [Message], server: PushServer?) {
        let now = Date.now
        var changed = false
        for message in messages where !message.isSender && message.id.hasPrefix("$") {
            guard !contains(message.id) else { continue }
            records[message.id] = SeenMessageRecord(
                message: SeenMessage(chatID: message.chatID, messageID: message.id), seenAt: now
            )
            changed = true
        }
        if changed {
            prune()
            save()
        }
        flush(server: server)
    }

    /// Retry on activation as well as new messages. An unsuccessful batch stays
    /// persisted until acknowledged, including if iOS suspends the upload.
    func flush(server: PushServer?) {
        guard let server, uploadTask == nil, records.values.contains(where: { !$0.isReported }) else { return }
        let generation = generation
        uploadTask = Task {
            defer { if self.generation == generation { uploadTask = nil } }
            var failures = 0
            while !Task.isCancelled {
                prune()
                let batch = Array(records.values.filter { !$0.isReported }
                    .sorted { $0.seenAt > $1.seenAt }.prefix(Self.batchSize))
                guard !batch.isEmpty else { return }
                do {
                    try await server.markSeen(batch.map(\.message))
                    try Task.checkCancellation()
                    guard self.generation == generation else { return }
                    for record in batch { records[record.message.messageID]?.isReported = true }
                    save()
                    failures = 0
                } catch {
                    guard !Task.isCancelled, self.generation == generation else { return }
                    failures += 1
                    logger.error("Seen-message upload failed; retaining batch of \(batch.count) (attempt \(failures))")
                    guard failures < 3 else { return }
                    do { try await Task.sleep(for: .seconds(failures * 2)) }
                    catch { return }
                }
            }
        }
    }

    func waitForUpload() async {
        await uploadTask?.value
    }

    func cancelUpload() {
        generation = UUID()
        uploadTask?.cancel()
        uploadTask = nil
    }

    func removeAll() {
        cancelUpload()
        records.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    private func prune() {
        let cutoff = Date.now.addingTimeInterval(-Self.window)
        records = records.filter { $0.value.seenAt > cutoff }
        if records.count > Self.capacity {
            records = Dictionary(uniqueKeysWithValues: records.sorted { $0.value.seenAt > $1.value.seenAt }
                .prefix(Self.capacity).map { ($0.key, $0.value) })
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
