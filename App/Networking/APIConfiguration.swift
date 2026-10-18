import Foundation

enum APIConfiguration {
    nonisolated static let baseURL = MatrixFiles.baseURL

    static var manageSecret: String { (try? MatrixFiles.configuration().manageSecret) ?? "" }
    static var assetsProxyURL: URL { baseURL.appending(path: "/v1/assets/serve") }
}
