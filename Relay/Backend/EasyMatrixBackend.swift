import Foundation
import Observation
import OSLog

/// Runs the EasyMatrix Go backend **in-process** on both macOS and iOS.
///
/// The backend ships as `EasyMatrix.xcframework` (a C static library, see
/// `Helpers/build-easymatrix-xcframework.sh`) and is started via its C ABI
/// (`EasyMatrixCreate` / `EasyMatrixServe`, declared in the bridging header).
/// It binds a localhost HTTP + WebSocket server inside the app process, which
/// the rest of the app talks to exactly as it would a standalone server —
/// `APIConfiguration.baseURL` still points at `127.0.0.1`.
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
    let manageSecret: String = UUID().uuidString

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Relay", category: "EasyMatrixBackend")
    private var handle: EasyMatrixHandle = 0

    /// Host:port the in-process backend binds. Must match `APIConfiguration.baseURL`.
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
            logger.info("EasyMatrix backend ready on \(APIConfiguration.baseURL.absoluteString, privacy: .public)")
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

    private func waitUntilReady() async throws {
        let deadline = Date().addingTimeInterval(45)
        let url = APIConfiguration.baseURL.appending(path: "/manage/state")
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
    func withMutableCString<R>(_ body: (UnsafeMutablePointer<CChar>) -> R) -> R {
        let copy = strdup(self)!
        defer { free(copy) }
        return body(copy)
    }
}
