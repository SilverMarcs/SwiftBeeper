#if os(iOS)
import AudioToolbox
import AVFAudio
import Foundation
import OSLog

/// Foreground conversation sounds. Background alerts remain owned by APNs.
@MainActor
final class MessageSounds {
    // Public playback API, private system asset paths. These are the Messages
    // conversation sounds, not the user's incoming notification alert tone.
    private let sentSound = MessageSounds.makeSound(named: "SentMessage")
    private let receivedSound = MessageSounds.makeSound(named: "ReceivedMessage")
    private var handledIDs: Set<String> = []
    private var activeSince: Date?
    private var queue: [SystemSoundID] = []
    private var playback: Task<Void, Never>?
    var notificationSoundsAllowed = false

    func setAppActive(_ active: Bool) {
        if active {
            if activeSince == nil { activeSince = .now }
        } else {
            activeSince = nil
            queue.removeAll()
        }
    }

    func reset() {
        handledIDs.removeAll()
        queue.removeAll()
    }

    func sent(_ message: Message) {
        guard message.id.hasPrefix("$"), message.deliveryStatus != .failed,
              handledIDs.insert(message.id).inserted else { return }
        enqueue(sentSound)
    }

    func received(messageID: String, timestamp: Date? = nil, isMuted: Bool = false, isMention: Bool = false,
                  fromForegroundNotification: Bool = false) {
        // willPresent establishes foreground delivery even before scenePhase
        // has caught up with activation.
        if fromForegroundNotification { setAppActive(true) }
        guard messageID.hasPrefix("$"), handledIDs.insert(messageID).inserted,
              let activeSince, timestamp.map({ $0 >= activeSince }) ?? true,
              notificationSoundsAllowed, !isMuted || isMention else { return }
        enqueue(receivedSound)
    }

    private func enqueue(_ sound: SystemSoundID?) {
        guard let sound, canPlay else { return }
        queue.append(sound)
        guard playback == nil else { return }
        playback = Task {
            defer { playback = nil }
            // System Sound Services supports only one sound at a time.
            while !queue.isEmpty {
                let next = queue.removeFirst()
                guard canPlay else { queue.removeAll(); return }
                await withCheckedContinuation { continuation in
                    AudioServicesPlaySystemSoundWithCompletion(next) { continuation.resume() }
                }
            }
        }
    }

    private var canPlay: Bool {
        activeSince != nil
            // Keep conversation sounds out of the dictation recording.
            && AVAudioSession.sharedInstance().category != .record
    }

    private static func makeSound(named name: String) -> SystemSoundID? {
        #if targetEnvironment(simulator)
        let root = ProcessInfo.processInfo.environment["SIMULATOR_ROOT"] ?? "/"
        #else
        let root = "/"
        #endif
        let url = URL(filePath: root).appending(path: "System/Library/Audio/UISounds/\(name).caf")
        var sound: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &sound)
        guard status == kAudioServicesNoError else {
            Logger(subsystem: "com.SilverMarcs.Relay", category: "sounds")
                .error("System sound \(name, privacy: .public) unavailable: \(status)")
            return nil
        }
        // System sounds default to IsUISound = 1, honoring silent mode and
        // the system sound-effects preference.
        return sound
    }

    // IDs are retained for the notification service's app lifetime.
    isolated deinit {
        if let sentSound { AudioServicesDisposeSystemSoundID(sentSound) }
        if let receivedSound { AudioServicesDisposeSystemSoundID(receivedSound) }
    }
}
#endif
