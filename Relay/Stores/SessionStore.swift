import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    private let keychain = KeychainManager.shared
    private static let legacyAccessTokenKey = "beeperAccessToken"
    private var endpointIdentity: String

    private var accessTokenKey: String {
        "beeperAccessToken|\(endpointIdentity)"
    }

    var accessToken: String {
        didSet { persistAccessToken(accessToken) }
    }

    init(endpointIdentity: String = "embedded") {
        self.endpointIdentity = endpointIdentity

        let scopedToken = keychain.load(key: "beeperAccessToken|\(endpointIdentity)")
        if let scopedToken {
            accessToken = scopedToken
        } else if endpointIdentity == ServerEndpoint.embedded.identity,
                  let legacyToken = keychain.load(key: Self.legacyAccessTokenKey) {
            accessToken = legacyToken
            keychain.save(key: "beeperAccessToken|\(endpointIdentity)", data: legacyToken)
        } else {
            accessToken = ""
        }
    }

    func clearToken() {
        accessToken = ""
    }

    func switchEndpoint(to identity: String, suppliedToken: String? = nil) {
        endpointIdentity = identity
        if let suppliedToken, !suppliedToken.isEmpty {
            accessToken = suppliedToken
        } else {
            accessToken = keychain.load(key: accessTokenKey) ?? ""
        }
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
