import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class EasyMatrixProcess {
    static let shared = EasyMatrixProcess()

    enum State: Equatable {
        case idle
        case starting
        case ready
        case stopping
        case crashed(String)
    }

    private(set) var state: State = .idle
    let manageSecret: String = UUID().uuidString

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SwiftBeeper", category: "EasyMatrixProcess")
    private var process: Process?
    private var stderrPipe: Pipe?

    private init() {}

    func start() async {
        if state == .ready || state == .starting { return }
        state = .starting

        Self.reapOrphans(logger: logger)

        do {
            let binaryURL = try Self.locateBinary()
            let gomuksRoot = try Self.gomuksRoot()
            try await launch(binary: binaryURL, gomuksRoot: gomuksRoot)
            try await waitUntilReady()
            state = .ready
            logger.info("EasyMatrix backend ready on \(APIConfiguration.baseURL.absoluteString, privacy: .public)")
        } catch {
            logger.error("Failed to start EasyMatrix backend: \(error.localizedDescription, privacy: .public)")
            state = .crashed(error.localizedDescription)
            cleanup()
        }
    }

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    func stop() async {
        guard let process, process.isRunning else {
            cleanup()
            state = .idle
            return
        }
        state = .stopping
        logger.info("Terminating EasyMatrix backend (pid \(process.processIdentifier, privacy: .public))")
        process.terminate()

        let deadline = Date().addingTimeInterval(2.0)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if process.isRunning {
            logger.warning("SIGTERM ignored — sending SIGKILL")
            kill(process.processIdentifier, SIGKILL)
        }
        cleanup()
        state = .idle
    }

    private func launch(binary: URL, gomuksRoot: URL) async throws {
        let process = Process()
        process.executableURL = binary
        process.environment = [
            "GOMUKS_ROOT": gomuksRoot.path(percentEncoded: false),
            "MATRIX_API_LISTEN": "127.0.0.1:23374",
            "EASYMATRIX_MANAGE_SECRET": manageSecret,
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        ]

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        self.stderrPipe = stderr

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            Task { @MainActor in
                self.handleTermination(reason: proc.terminationReason, status: proc.terminationStatus)
            }
        }

        Task.detached { [weak self] in
            let handle = stderr.fileHandleForReading
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                if let line = String(data: data, encoding: .utf8) {
                    await self?.logStderr(line)
                }
            }
        }

        try process.run()
        self.process = process
        logger.info("Spawned easymatrix (pid \(process.processIdentifier, privacy: .public))")
    }

    private func waitUntilReady() async throws {
        let deadline = Date().addingTimeInterval(45)
        let url = APIConfiguration.baseURL.appending(path: "/manage/state")
        var lastError: Error?

        while Date() < deadline {
            if let process, !process.isRunning {
                let status = process.terminationStatus
                logger.warning("Backend exited (status \(status, privacy: .public)) before ready — relaunching")
                cleanup()
                try await Task.sleep(for: .seconds(2))
                let binaryURL = try Self.locateBinary()
                let gomuksRoot = try Self.gomuksRoot()
                try await launch(binary: binaryURL, gomuksRoot: gomuksRoot)
                continue
            }

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

    private func handleTermination(reason: Process.TerminationReason, status: Int32) {
        let reasonText = reason == .uncaughtSignal ? "signal \(status)" : "exit \(status)"
        logger.error("EasyMatrix exited unexpectedly (\(reasonText, privacy: .public))")
        if state == .ready || state == .starting {
            state = .crashed("Backend exited (\(reasonText)). Check Console.app for easymatrix logs.")
        }
        cleanup()
    }

    private func logStderr(_ line: String) {
        for raw in line.split(whereSeparator: \.isNewline) {
            logger.debug("[easymatrix] \(raw, privacy: .public)")
        }
    }

    private func cleanup() {
        process = nil
        stderrPipe = nil
    }

    /// Kill any easymatrix process still bound to the management port from a
    /// previous run that didn't shut down cleanly (crash, force-quit, Xcode
    /// stop button — none of which trigger `applicationWillTerminate`).
    static func reapOrphans(logger: Logger) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-ti", "tcp:23374"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return }
        let pids = output
            .split(whereSeparator: { $0.isNewline })
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 > 0 && $0 != getpid() }

        guard !pids.isEmpty else { return }

        for pid in pids {
            logger.warning("Reaping orphaned backend pid \(pid, privacy: .public)")
            kill(pid, SIGTERM)
        }

        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline, pids.contains(where: { kill($0, 0) == 0 }) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        for pid in pids where kill(pid, 0) == 0 {
            logger.warning("Orphan pid \(pid, privacy: .public) ignored SIGTERM — sending SIGKILL")
            kill(pid, SIGKILL)
        }
    }

    static func locateBinary() throws -> URL {
        let bundleURL = Bundle.main.bundleURL
        let url = bundleURL.appending(path: "Contents/Helpers/easymatrix")
        guard FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false)) else {
            throw BackendError.binaryMissing(url.path(percentEncoded: false))
        }
        return url
    }

    static func gomuksRoot() throws -> URL {
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
    case binaryMissing(String)
    case exited(status: Int32)
    case timeout(String?)

    var errorDescription: String? {
        switch self {
        case .binaryMissing(let path):
            return "Embedded backend not found at \(path)."
        case .exited(let status):
            return "Backend exited before becoming ready (status \(status))."
        case .timeout(let detail):
            if let detail, !detail.isEmpty {
                return "Backend did not respond within 15 s: \(detail)"
            }
            return "Backend did not respond within 15 s."
        }
    }
}
