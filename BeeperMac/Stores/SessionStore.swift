import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    private let keychain = KeychainManager.shared
    private let defaults = UserDefaults.standard
    private let accessTokenKey = "beeperAccessToken"
    private let currentUserIDKey = "beeperUserID"

    var accessToken: String {
        didSet {
            persistAccessToken(accessToken)
        }
    }

    var currentUserID: String {
        didSet {
            defaults.set(currentUserID, forKey: currentUserIDKey)
        }
    }

    init() {
        accessToken = keychain.load(key: accessTokenKey) ?? ""
        currentUserID = defaults.string(forKey: currentUserIDKey) ?? ""
    }

    func clearToken() {
        accessToken = ""
    }

    private func persistAccessToken(_ value: String) {
        if value.isEmpty {
            keychain.delete(key: accessTokenKey)
            return
        }

        keychain.save(key: accessTokenKey, data: value)
    }
}
