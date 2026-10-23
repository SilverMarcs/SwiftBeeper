#if os(iOS)
import SwiftUI

extension EnvironmentValues {
    /// Offscreen row measurement must not start the real bubble's send clock.
    @Entry var messageSendAnimationsEnabled = true
}
#endif
