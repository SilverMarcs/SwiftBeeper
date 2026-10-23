import Foundation
import Observation

/// Whether the Matrix core has a signed-in, verified account. The core owns
/// the credentials; this only drives which UI shows.
@MainActor
@Observable
final class SessionStore {
    var isSignedIn = false
}
