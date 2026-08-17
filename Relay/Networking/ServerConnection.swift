import Foundation
import Observation
import OSLog

struct ServerEndpoint: Equatable, Sendable {
    /// Stand-in for "Relay has not been pointed at a server yet". `.invalid` is
    /// a reserved TLD, so any request that slips past the onboarding gate fails
    /// fast instead of quietly reaching something real.
    nonisolated static let unconfigured = ServerEndpoint(
        baseURL: URL(string: "https://unconfigured.invalid")!,
        isConfigured: false
    )

    let baseURL: URL
    let isConfigured: Bool

    nonisolated var identity: String {
        isConfigured ? baseURL.absoluteString : "unconfigured"
    }

    nonisolated static func remote(from input: String) throws -> ServerEndpoint {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ServerConnectionError.invalidURL }

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
        return ServerEndpoint(baseURL: url, isConfigured: true)
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

/// Owns the remote EasyMatrix server Relay talks to: which URL, and the
/// administrative secret for it. Every runtime is remote — the client never
/// hosts a backend itself.
@MainActor
@Observable
final class ServerConnection {
    private static let remoteURLKey = "server.remoteURL"
    nonisolated private static let manageSecretKeyPrefix = "serverManageSecret|"

    private let defaults: UserDefaults
    private let keychain: KeychainManager
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Relay",
        category: "ServerConnection"
    )

    private(set) var endpoint: ServerEndpoint
    private(set) var isUpdatingRemoteServer = false
    private var activeManageSecret: String

    convenience init() {
        self.init(defaults: .standard, keychain: .shared)
    }

    init(defaults: UserDefaults, keychain: KeychainManager) {
        self.defaults = defaults
        self.keychain = keychain

        let savedURL = defaults.string(forKey: Self.remoteURLKey) ?? ""
        let savedEndpoint = try? ServerEndpoint.remote(from: savedURL)
        endpoint = savedEndpoint ?? .unconfigured
        activeManageSecret = savedEndpoint.flatMap {
            keychain.load(key: Self.manageSecretKey(for: $0))
        } ?? ""
        APIConfiguration.configure(endpoint: endpoint, manageSecret: activeManageSecret)
    }

    var remoteURLString: String {
        endpoint.isConfigured ? endpoint.baseURL.absoluteString : ""
    }

    var needsRemoteConfiguration: Bool {
        !endpoint.isConfigured
    }

    /// Validates and persists a new remote endpoint.
    @discardableResult
    func updateRemoteServer(
        remoteURL input: String,
        manageSecret suppliedManageSecret: String? = nil
    ) async throws -> Bool {
        let newEndpoint = try ServerEndpoint.remote(from: input)
        let endpointChanged = newEndpoint != endpoint
        let newManageSecret: String
        if let suppliedManageSecret, !suppliedManageSecret.isEmpty {
            newManageSecret = suppliedManageSecret
        } else if endpointChanged {
            newManageSecret = keychain.load(key: Self.manageSecretKey(for: newEndpoint)) ?? ""
        } else {
            newManageSecret = activeManageSecret
        }

        guard endpointChanged || newManageSecret != activeManageSecret else {
            return false
        }

        isUpdatingRemoteServer = true
        defer { isUpdatingRemoteServer = false }

        if endpointChanged {
            try await validate(newEndpoint)
        }

        endpoint = newEndpoint
        activeManageSecret = newManageSecret
        APIConfiguration.configure(endpoint: endpoint, manageSecret: activeManageSecret)
        defaults.set(endpoint.baseURL.absoluteString, forKey: Self.remoteURLKey)
        if let suppliedManageSecret, !suppliedManageSecret.isEmpty {
            keychain.save(
                key: Self.manageSecretKey(for: endpoint),
                data: suppliedManageSecret
            )
        }

        logger.info("Using remote server \(self.endpoint.baseURL.absoluteString, privacy: .public)")
        return true
    }

    func validateRemoteAccess(remoteURL input: String, accessKey: String) async throws {
        let endpoint = try ServerEndpoint.remote(from: input)
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
