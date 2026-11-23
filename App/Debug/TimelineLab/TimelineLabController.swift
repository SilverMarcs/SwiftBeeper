#if DEBUG
import Foundation
import Observation

/// Which lab chat is open. `RELAY_TIMELINE_LAB=1` swaps the app's root for
/// `TimelineLabRootView`, which opens these instead of Matrix chats.
@MainActor
@Observable
final class TimelineLabController {
    static let shared = TimelineLabController()

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["RELAY_TIMELINE_LAB"] != nil
    }

    var path: [String] = []
    @ObservationIgnored private(set) var sources: [String: TimelineLabSource] = [:]

    /// Opens a fresh copy of the fixture's chat.
    @discardableResult
    func open(_ fixture: TimelineLabFixture, loadDelay: Duration? = nil) -> TimelineLabSource {
        let source = TimelineLabSource(fixture: fixture, loadDelay: loadDelay)
        let key = "\(fixture.rawValue)-\(UUID().uuidString)"
        sources[key] = source
        path.append(key)
        return source
    }

    func pop() {
        guard let key = path.popLast() else { return }
        Task {
            try? await Task.sleep(for: .seconds(1))
            sources[key] = nil
        }
    }
}
#endif
