import Foundation
import Observation

/// The UI's session generation. Matrix authentication is owned by Go.
@MainActor
@Observable
final class SessionStore {
    var accessToken = ""

    init() {}

    func clearToken() { accessToken = "" }

}
