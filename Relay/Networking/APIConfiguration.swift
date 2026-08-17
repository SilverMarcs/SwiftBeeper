import Foundation

enum APIConfiguration {
    private static let storage = Storage()

    static var baseURL: URL {
        storage.snapshot.endpoint.baseURL
    }

    static var endpointIdentity: String {
        storage.snapshot.endpoint.identity
    }

    static var manageSecret: String {
        storage.snapshot.manageSecret
    }

    static var assetsProxyURL: URL {
        baseURL.appending(path: "/v1/assets/serve")
    }

    static var webSocketURL: URL {
        var components = URLComponents(url: baseURL.appending(path: "/v1/ws"), resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        return components?.url ?? baseURL.appending(path: "/v1/ws")
    }

    static func configure(endpoint: ServerEndpoint, manageSecret: String) {
        storage.update(endpoint: endpoint, manageSecret: manageSecret)
    }
}

private final class Storage: @unchecked Sendable {
    struct Snapshot {
        let endpoint: ServerEndpoint
        let manageSecret: String
    }

    private let lock = NSLock()
    private var value = Snapshot(endpoint: .unconfigured, manageSecret: "")

    var snapshot: Snapshot {
        lock.withLock { value }
    }

    func update(endpoint: ServerEndpoint, manageSecret: String) {
        lock.withLock {
            value = Snapshot(endpoint: endpoint, manageSecret: manageSecret)
        }
    }
}
