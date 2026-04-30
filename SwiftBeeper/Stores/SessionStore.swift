import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    private let keychain = KeychainManager.shared
    private let accessTokenKey = "beeperAccessToken"

    var accessToken: String {
        didSet {
            persistAccessToken(accessToken)
        }
    }

    init() {
        accessToken = keychain.load(key: accessTokenKey) ?? ""
    }

    func clearToken() {
        accessToken = ""
    }

    /// Mints a fresh manage access token. Used to recover from a 401 when the
    /// previous token has expired (24h TTL); the gomuks login session itself
    /// outlives individual access tokens, so refresh succeeds as long as the
    /// user hasn't actually signed out of Matrix.
    func refreshAccessToken() async throws -> String {
        let response = try await APIClient.mintAccessToken()
        accessToken = response.accessToken
        APIClient.accessToken = response.accessToken
        return response.accessToken
    }

    private func persistAccessToken(_ value: String) {
        if value.isEmpty {
            keychain.delete(key: accessTokenKey)
            return
        }

        keychain.save(key: accessTokenKey, data: value)
    }
}
