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
            refreshFailed = false
        }
    }

    /// True while a token refresh is in flight. UI can show a ProgressView
    /// instead of a 401 error during the brief refresh window.
    var isRefreshingToken: Bool = false

    /// Set when the most recent refresh attempt threw. UI can show a
    /// "Session Expired — Reconnect" affordance instead of dumping the user
    /// back to the missing-token state.
    var refreshFailed: Bool = false

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
        isRefreshingToken = true
        defer { isRefreshingToken = false }
        do {
            let response = try await APIClient.mintAccessToken()
            accessToken = response.accessToken
            APIClient.accessToken = response.accessToken
            return response.accessToken
        } catch {
            refreshFailed = true
            throw error
        }
    }

    private func persistAccessToken(_ value: String) {
        if value.isEmpty {
            keychain.delete(key: accessTokenKey)
            return
        }

        keychain.save(key: accessTokenKey, data: value)
    }
}
