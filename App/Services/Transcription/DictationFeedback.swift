import Foundation

/// A dictation moment the composer taps for, distinct even when the same
/// kind happens twice in succession.
struct DictationFeedback: Equatable {
    enum Kind {
        /// The microphone is recording.
        case recordingStarted
        /// A transcript landed in the draft.
        case transcriptReady
        /// Send while recording: one tap for the whole transcribe-and-send.
        case send
    }

    let kind: Kind
    private let id = UUID()

    init(_ kind: Kind) {
        self.kind = kind
    }
}
