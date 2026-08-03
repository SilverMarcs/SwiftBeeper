import Foundation
import Observation
import OSLog

#if !REMOTE_ONLY
/// Runs the EasyMatrix Go backend **in-process** on both macOS and iOS.
///
/// The backend ships as `EasyMatrix.xcframework` (a C static library, see
/// `Helpers/build-easymatrix-xcframework.sh`) and is started via its C ABI
/// (`EasyMatrixCreate` / `EasyMatrixServe`, declared in the bridging header).
/// It binds a localhost HTTP + WebSocket server inside the app process, which
/// the rest of the app talks to exactly as it would a standalone server.
///
/// This replaces the old macOS-only model that spawned the backend as a child
/// `Process`. Spawning subprocesses is forbidden on iOS; binding a localhost
/// socket inside the app is not, so a single in-process path serves both.
@MainActor
@Observable
final class EasyMatrixBackend {
    static let shared = EasyMatrixBackend()

    enum State: Equatable {
        case idle
        case starting
        case ready
        case stopping
        case crashed(String)
    }

    private(set) var state: State = .idle
    /// True once the backend has reached `.ready` at least once this app run.
    /// Lets `BackendGate` distinguish first launch (full-screen loading view)
    /// from a foreground-recovery restart (content stays up, silent reconnect).
    private(set) var hasEverBeenReady = false
    let manageSecret: String = UUID().uuidString

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Relay", category: "EasyMatrixBackend")
    private var handle: EasyMatrixHandle = 0

    /// Host:port the in-process backend binds.
    private static let listenAddr = "127.0.0.1:23374"

    private init() {}

    var isRunning: Bool {
        handle != 0 && state == .ready
    }

    func start() async {
        if state == .ready || state == .starting { return }
        state = .starting

        let stateDir: String
        do {
            stateDir = try Self.stateDirectory().path(percentEncoded: false)
        } catch {
            logger.error("Failed to prepare state directory: \(error.localizedDescription, privacy: .public)")
            state = .crashed(error.localizedDescription)
            return
        }

        let configJSON = Self.makeConfigJSON(stateDir: stateDir, manageSecret: manageSecret)
        let listenAddr = Self.listenAddr

        // EasyMatrixCreate/Serve do blocking work (DB open, gomuks start), so run
        // them off the main actor to keep the UI responsive.
        let startedHandle = await Task.detached(priority: .userInitiated) { () -> EasyMatrixHandle in
            let created = configJSON.withMutableCString { EasyMatrixCreate($0) }
            guard created != 0 else { return 0 }
            let serveResult = listenAddr.withMutableCString { EasyMatrixServe(created, $0) }
            guard serveResult == 0 else {
                EasyMatrixDestroy(created)
                return 0
            }
            return created
        }.value

        guard startedHandle != 0 else {
            let detail = Self.lastBackendError()
            logger.error("EasyMatrix backend failed to start: \(detail, privacy: .public)")
            state = .crashed(detail.isEmpty ? "Backend failed to start." : detail)
            return
        }
        handle = startedHandle

        do {
            try await waitUntilReady()
            state = .ready
            hasEverBeenReady = true
            logger.info("EasyMatrix backend ready on \(ServerEndpoint.embedded.baseURL.absoluteString, privacy: .public)")
        } catch {
            logger.error("Backend did not become ready: \(error.localizedDescription, privacy: .public)")
            state = .crashed(error.localizedDescription)
            await stop()
        }
    }

    func stop() async {
        guard handle != 0 else {
            state = .idle
            return
        }
        state = .stopping
        let toStop = handle
        handle = 0
        logger.info("Stopping in-process EasyMatrix backend")
        await Task.detached(priority: .userInitiated) {
            EasyMatrixStop(toStop)
            EasyMatrixDestroy(toStop)
        }.value
        state = .idle
    }

    /// Called when the app returns to the foreground. While iOS suspends the
    /// process, it tears down the embedded server's listening socket, so requests
    /// fail with "Could not connect to the server" even though `state` still reads
    /// `.ready`. Probe the server and, if it's no longer accepting connections,
    /// restart it (`BackendGate` keeps the content up during the reboot because
    /// `hasEverBeenReady` is already set, so the restart is invisible).
    func recoverIfNeeded() async {
        switch state {
        case .idle, .starting, .stopping:
            // Initial startup (RootView's `.task`) owns these transitions.
            return
        case .crashed:
            await start()
        case .ready:
            if await isServerReachable() { return }
            logger.info("Backend unreachable after returning to foreground — rebinding")
            await resume()
        }
    }

    /// Cheap foreground recovery. iOS reaps the process's sockets while it is
    /// suspended, so the localhost listener is dead on return — but the Matrix
    /// client, database, and crypto store all live on in memory. Rebind a fresh
    /// socket onto them (`EasyMatrixResume`) instead of tearing the whole
    /// backend down and cold-booting it: the old `stop()` + `start()` path paid
    /// a 5 s graceful-shutdown ceiling, a DB close/reopen, a crypto reload, and
    /// a synchronous homeserver `/versions` call — seconds of dead time on every
    /// foreground. `state` stays `.ready` throughout so `BackendGate` keeps the
    /// UI up and the rebind is invisible. Falls back to a full restart if the
    /// rebind fails or the server doesn't answer afterwards.
    func resume() async {
        guard handle != 0, state == .ready else {
            // Nothing live to rebind onto (never started, or mid-transition).
            await start()
            return
        }

        let listenAddr = Self.listenAddr
        let currentHandle = handle
        let rebound = await Task.detached(priority: .userInitiated) { () -> Bool in
            listenAddr.withMutableCString { EasyMatrixResume(currentHandle, $0) == 0 }
        }.value

        guard rebound else {
            logger.info("Rebind failed (\(Self.lastBackendError(), privacy: .public)) — full restart")
            await stop()
            await start()
            return
        }

        do {
            try await waitUntilReady()
            logger.info("EasyMatrix backend rebound after returning to foreground")
        } catch {
            logger.error("Backend not ready after rebind — full restart: \(error.localizedDescription, privacy: .public)")
            await stop()
            await start()
        }
    }

    private func isServerReachable() async -> Bool {
        let url = ServerEndpoint.embedded.baseURL.appending(path: "/manage/state")
        
        for attempt in 1...3 {
            var request = URLRequest(url: url, timeoutInterval: 1.0)
            request.setValue(manageSecret, forHTTPHeaderField: "X-EasyMatrix-Manage-Secret")
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200..<500).contains(http.statusCode) {
                    return true
                }
            } catch {
                logger.info("Reachability probe attempt \(attempt) failed: \(error.localizedDescription, privacy: .public)")
            }
            if attempt < 3 {
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        return false
    }

    private func waitUntilReady() async throws {
        let deadline = Date().addingTimeInterval(45)
        let url = ServerEndpoint.embedded.baseURL.appending(path: "/manage/state")
        var lastError: Error?

        while Date() < deadline {
            var request = URLRequest(url: url, timeoutInterval: 1.0)
            request.setValue(manageSecret, forHTTPHeaderField: "X-EasyMatrix-Manage-Secret")
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200..<500).contains(http.statusCode) {
                    return
                }
            } catch {
                lastError = error
            }
            try await Task.sleep(for: .milliseconds(150))
        }

        throw BackendError.timeout(lastError?.localizedDescription)
    }

    private static func lastBackendError() -> String {
        guard let cString = EasyMatrixLastError() else { return "" }
        defer { EasyMatrixFreeCString(cString) }
        return String(cString: cString)
    }

    private static func makeConfigJSON(stateDir: String, manageSecret: String) -> String {
        let config: [String: Any] = [
            "listenAddr": listenAddr,
            "stateDir": stateDir,
            "manageSecret": manageSecret,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: config),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    /// State lives in the app's sandbox container on every platform — no more
    /// `HOME`/`NSHomeDirectory` env juggling that only worked on macOS.
    static func stateDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appending(path: "SwiftBeeper/gomuks")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

enum BackendError: LocalizedError {
    case startFailed
    case timeout(String?)

    var errorDescription: String? {
        switch self {
        case .startFailed:
            return "The embedded backend failed to start."
        case .timeout(let detail):
            if let detail, !detail.isEmpty {
                return "Backend did not respond within 45 s: \(detail)"
            }
            return "Backend did not respond within 45 s."
        }
    }
}

private extension String {
    /// Calls `body` with a mutable, NUL-terminated copy of this string. The Go
    /// FFI takes `char*`; the copy is freed when `body` returns.
    nonisolated func withMutableCString<R>(_ body: (UnsafeMutablePointer<CChar>) -> R) -> R {
        let copy = strdup(self)!
        defer { free(copy) }
        return body(copy)
    }
}
#endif
