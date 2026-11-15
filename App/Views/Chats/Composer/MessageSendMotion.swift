import SwiftUI

/// The send animation's timing, sampled from one clock so a flight carries on
/// unbroken when the optimistic row is replaced by its echo.
///
/// The bubble glides across to its side a little faster than it rises, so it
/// curves gently up out of the field, and springs into place, overshooting
/// a little and settling back, as in Messages. The timeline scrolls on the
/// same spring, so the conversation bounces up with it.
nonisolated enum MessageSendMotion {
    /// Shorten every phase together, keeping the path, bounce and scroll in sync.
    private static let timingScale = 0.85

    /// When every curve has settled and the real bubble takes over.
    static let duration: TimeInterval = 0.75 * timingScale

    /// About 7% overshoot as it arrives.
    private static let riseSpring = Spring(duration: 0.45 * timingScale, bounce: 0.35)
    /// No bounce, so the bubble never passes its side's edge.
    private static let slideSpring = Spring(duration: 0.34 * timingScale, bounce: 0)

    /// The timeline's scroll down to the sent message.
    static let scrollAnimation = Animation.spring(riseSpring)

    /// Seconds since the flight started, or zero before it has.
    static func elapsed(since start: ContinuousClock.Instant?, at now: ContinuousClock.Instant) -> TimeInterval {
        guard let start else { return 0 }
        return max(0, start.duration(to: now) / .seconds(1))
    }

    /// Vertical progress, 0 at the composer and 1 at the bubble.
    static func rise(at time: TimeInterval) -> CGFloat {
        progress(of: riseSpring, at: time)
    }

    /// Horizontal progress, 0 at the composer and 1 at the bubble.
    static func slide(at time: TimeInterval) -> CGFloat {
        progress(of: slideSpring, at: time)
    }

    /// Whether the text has taken the bubble's lines, from the composer's,
    /// which is narrower, so a longer message wraps differently in each. It
    /// changes in one frame, once the bubble moves fast enough for the change
    /// to read as part of the motion: words sliding or fading between lines
    /// show as a jumble while they cross.
    static func hasReflowed(at time: TimeInterval) -> Bool {
        time >= 0.08 * timingScale
    }

    private static func progress(of spring: Spring, at time: TimeInterval) -> CGFloat {
        guard time < duration else { return 1 }
        return spring.value(target: CGFloat(1), time: max(0, time))
    }
}
