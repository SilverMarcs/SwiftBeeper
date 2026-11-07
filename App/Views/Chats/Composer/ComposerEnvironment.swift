import SwiftUI

extension EnvironmentValues {
    /// The composer of the conversation a message row renders in: the chat's,
    /// or a thread's. Message actions such as Reply and Edit use it.
    @Entry var composer: Composer?
}
