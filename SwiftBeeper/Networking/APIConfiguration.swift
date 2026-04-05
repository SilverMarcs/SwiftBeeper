import Foundation

enum APIConfiguration {
    static let baseURL = URL(string: "http://localhost:23373")!
    static let assetsProxyURL = baseURL.appending(path: "/v1/assets/serve")

    static var webSocketURL: URL {
        var components = URLComponents(url: baseURL.appending(path: "/v1/ws"), resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        return components?.url ?? baseURL.appending(path: "/v1/ws")
    }
}
