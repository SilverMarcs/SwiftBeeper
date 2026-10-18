import Foundation
import Observation

/// The UI's local dispatcher token. Matrix authentication is owned by Go.
@MainActor
@Observable
final class SessionStore {
    var accessToken = ""

    init() {}

    func clearToken() { accessToken = "" }

}
