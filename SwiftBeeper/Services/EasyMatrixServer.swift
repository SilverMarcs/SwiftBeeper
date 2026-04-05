import Foundation
import OSLog

/// Manages the EasyMatrix server process lifecycle.
/// Launches the server when the app starts and terminates it when the app quits.
final class EasyMatrixServer {
    static let shared = EasyMatrixServer()

    private let logger = Logger(subsystem: "SwiftBeeper", category: "EasyMatrixServer")
    private var process: Process?
    private let binaryPath: String
    private let port = "23374"
    private let accessToken = "hytmiz-nesxuw-rEgwi2"

    private init() {
        binaryPath = NSString("~/bin/easymatrix").expandingTildeInPath
    }

    func start() {
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            logger.warning("EasyMatrix binary not found at \(self.binaryPath)")
            return
        }

        // Don't start if already running (e.g. from a previous session)
        if isPortInUse() {
            logger.info("EasyMatrix already running on port \(self.port)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        // Set working directory to the binary's directory so @executable_path dylibs resolve
        process.currentDirectoryURL = URL(fileURLWithPath: binaryPath).deletingLastPathComponent()
        process.environment = [
            "MATRIX_API_LISTEN": "127.0.0.1:\(port)",
            "MATRIX_ACCESS_TOKEN": accessToken,
            "MATRIX_ALLOW_QUERY_TOKEN": "true",
            "HOME": NSHomeDirectory(),
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            self.process = process
            logger.info("EasyMatrix server started (PID \(process.processIdentifier))")
            waitUntilReady()
        } catch {
            logger.error("Failed to start EasyMatrix: \(error.localizedDescription)")
        }
    }

    /// Blocks until the server is accepting connections (up to 10 seconds).
    private func waitUntilReady() {
        for _ in 0..<40 {
            if isPortInUse() {
                logger.info("EasyMatrix server is ready")
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        logger.warning("EasyMatrix server did not become ready in time")
    }

    func stop() {
        guard let process, process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
        self.process = nil
        logger.info("EasyMatrix server stopped")
    }

    private func isPortInUse() -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port)!.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
