import Foundation
import Observation
import OSLog

struct ServerEndpoint: Equatable, Sendable {
    nonisolated static let embedded = ServerEndpoint(
        baseURL: URL(string: "http://127.0.0.1:23374")!,
        isEmbedded: true
    )

    let baseURL: URL
    let isEmbedded: Bool

    nonisolated var identity: String {
        isEmbedded ? "embedded" : baseURL.absoluteString
    }

    nonisolated static func remote(from input: String) throws -> ServerEndpoint {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .embedded }

        if !value.contains("://") {
            value = "https://\(value)"
        }

        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil else {
            throw ServerConnectionError.invalidURL
        }

        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        if components.path == "/" {
            components.path = ""
        } else {
            let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = path.isEmpty ? "" : "/\(path)"
        }

        guard let url = components.url else {
            throw ServerConnectionError.invalidURL
        }
        return ServerEndpoint(baseURL: url, isEmbedded: false)
    }
}

enum ServerConnectionError: LocalizedError {
    case invalidURL
    case unavailable(String)
    case invalidAccessKey
    case invalidSetupSecret

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid HTTP or HTTPS server URL."
        case .unavailable(let detail):
            return "Relay could not reach that server. \(detail)"
        case .invalidAccessKey:
            return "The Server Access Key was not accepted."
        case .invalidSetupSecret:
            return "The administrative setup secret was not accepted."
        }
    }
}

/// Owns the only client/server choice in the app. Views and stores keep using
/// the same API surface regardless of whether it is backed by the embedded
/// runtime or a remote EasyMatrix instance.
@MainActor
@Observable
final class ServerConnection {
    private static let remoteURLKey = "server.remoteURL"
    private static let selectionCompletedKey = "server.selectionCompleted"
    private static let embeddedAccessTokenKey = "beeperAccessToken|embedded"
    private static let legacyAccessTokenKey = "beeperAccessToken"
    nonisolated private static let manageSecretKeyPrefix = "serverManageSecret|"

    let backend: EasyMatrixBackend
    private let defaults: UserDefaults
    private let keychain: KeychainManager
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Relay",
        category: "ServerConnection"
    )

    private(set) var endpoint: ServerEndpoint
    private(set) var isSwitching = false
    private(set) var needsInitialSelection: Bool
    private var activeManageSecret: String

    convenience init() {
        self.init(
            backend: .shared,
            defaults: .standard,
            keychain: .shared
        )
    }

    init(
        backend: EasyMatrixBackend,
        defaults: UserDefaults,
        keychain: KeychainManager
    ) {
        self.backend = backend
        self.defaults = defaults
        self.keychain = keychain

        let savedURL = defaults.string(forKey: Self.remoteURLKey) ?? ""
        let initialEndpoint = (try? ServerEndpoint.remote(from: savedURL)) ?? .embedded
        let hasExistingEmbeddedSession =
            keychain.load(key: Self.embeddedAccessTokenKey) != nil
            || keychain.load(key: Self.legacyAccessTokenKey) != nil
        needsInitialSelection =
            !defaults.bool(forKey: Self.selectionCompletedKey)
            && savedURL.isEmpty
            && !hasExistingEmbeddedSession
        let initialManageSecret = initialEndpoint.isEmbedded
            ? backend.manageSecret
            : keychain.load(key: Self.manageSecretKey(for: initialEndpoint)) ?? ""
        endpoint = initialEndpoint
        activeManageSecret = initialManageSecret
        APIConfiguration.configure(endpoint: initialEndpoint, manageSecret: initialManageSecret)
    }

    var remoteURLString: String {
        endpoint.isEmbedded ? "" : endpoint.baseURL.absoluteString
    }

    var usesEmbeddedServer: Bool {
        endpoint.isEmbedded
    }

    var hasRemoteManageSecret: Bool {
        !usesEmbeddedServer && !activeManageSecret.isEmpty
    }

    var isReady: Bool {
        needsInitialSelection || !usesEmbeddedServer || backend.state == .ready
    }

    var hasEverBeenReady: Bool {
        needsInitialSelection || !usesEmbeddedServer || backend.hasEverBeenReady
    }

    var failureMessage: String? {
        guard usesEmbeddedServer, case .crashed(let message) = backend.state else {
            return nil
        }
        return message
    }

    func prepare() async {
        APIConfiguration.configure(endpoint: endpoint, manageSecret: activeManageSecret)
        guard !needsInitialSelection else { return }
        guard usesEmbeddedServer else {
            // The remote path intentionally does not initialize or probe the
            // embedded Go/Matrix runtime.
            if backend.isRunning {
                await backend.stop()
            }
            return
        }
        await backend.start()
    }

    func selectEmbeddedServer() async {
        defaults.set(true, forKey: Self.selectionCompletedKey)
        needsInitialSelection = false
        endpoint = .embedded
        activeManageSecret = backend.manageSecret
        APIConfiguration.configure(endpoint: endpoint, manageSecret: activeManageSecret)
        defaults.removeObject(forKey: Self.remoteURLKey)
        await backend.start()
    }

    /// Validates and persists a new endpoint, then transitions runtimes without
    /// requiring the rest of the app to know which transport is in use.
    @discardableResult
    func switchServer(
        remoteURL input: String,
        manageSecret suppliedManageSecret: String? = nil
    ) async throws -> Bool {
        let newEndpoint = try ServerEndpoint.remote(from: input)
        let endpointChanged = newEndpoint != endpoint
        let newManageSecret: String
        if newEndpoint.isEmbedded {
            newManageSecret = backend.manageSecret
        } else if let suppliedManageSecret, !suppliedManageSecret.isEmpty {
            newManageSecret = suppliedManageSecret
        } else if endpointChanged {
            newManageSecret = keychain.load(key: Self.manageSecretKey(for: newEndpoint)) ?? ""
        } else {
            newManageSecret = activeManageSecret
        }

        guard endpointChanged || newManageSecret != activeManageSecret else {
            return false
        }

        isSwitching = true
        defer { isSwitching = false }

        if endpointChanged && !newEndpoint.isEmbedded {
            try await validate(newEndpoint)
        }

        if endpointChanged && backend.isRunning {
            await backend.stop()
        }

        endpoint = newEndpoint
        activeManageSecret = newManageSecret
        needsInitialSelection = false
        defaults.set(true, forKey: Self.selectionCompletedKey)
        APIConfiguration.configure(endpoint: endpoint, manageSecret: activeManageSecret)

        if endpoint.isEmbedded {
            defaults.removeObject(forKey: Self.remoteURLKey)
            if endpointChanged {
                await backend.start()
            }
        } else {
            defaults.set(endpoint.baseURL.absoluteString, forKey: Self.remoteURLKey)
            if let suppliedManageSecret, !suppliedManageSecret.isEmpty {
                keychain.save(
                    key: Self.manageSecretKey(for: endpoint),
                    data: suppliedManageSecret
                )
            }
        }

        logger.info("Using \(self.endpoint.isEmbedded ? "embedded" : "remote", privacy: .public) server")
        return true
    }

    func clearRemoteManageSecret() {
        guard !usesEmbeddedServer else { return }
        keychain.delete(key: Self.manageSecretKey(for: endpoint))
        activeManageSecret = ""
        APIConfiguration.configure(endpoint: endpoint, manageSecret: "")
    }

    func retry() async {
        if usesEmbeddedServer {
            await backend.start()
        }
    }

    func recoverIfNeeded() async {
        guard usesEmbeddedServer else { return }
        await backend.recoverIfNeeded()
    }

    func validateRemoteAccess(remoteURL input: String, accessKey: String) async throws {
        let endpoint = try ServerEndpoint.remote(from: input)
        guard !endpoint.isEmbedded else {
            throw ServerConnectionError.invalidURL
        }
        try await validate(endpoint)

        let url = endpoint.baseURL.appending(path: "/v1/accounts")
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Bearer \(accessKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode) else {
            throw ServerConnectionError.invalidAccessKey
        }
    }

    func validateRemoteManagement(remoteURL input: String, setupSecret: String) async throws {
        let endpoint = try ServerEndpoint.remote(from: input)
        guard !endpoint.isEmbedded else {
            throw ServerConnectionError.invalidURL
        }
        try await validate(endpoint)

        let url = endpoint.baseURL.appending(path: "/manage/state")
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue(setupSecret, forHTTPHeaderField: "X-EasyMatrix-Manage-Secret")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode) else {
            throw ServerConnectionError.invalidSetupSecret
        }
    }

    private func validate(_ endpoint: ServerEndpoint) async throws {
        let url = endpoint.baseURL.appending(path: "/v1/info")
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode) else {
                throw ServerConnectionError.unavailable("The health check returned an unexpected response.")
            }
        } catch let error as ServerConnectionError {
            throw error
        } catch {
            throw ServerConnectionError.unavailable(error.localizedDescription)
        }
    }

    nonisolated private static func manageSecretKey(for endpoint: ServerEndpoint) -> String {
        "\(manageSecretKeyPrefix)\(endpoint.identity)"
    }
}
