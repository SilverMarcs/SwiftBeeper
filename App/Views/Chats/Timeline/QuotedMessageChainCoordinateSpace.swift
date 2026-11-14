import SwiftUI

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    /// A tapped quote's chain, with its origin at the chain's bottom edge,
    /// where the reply's bubble starts. Positions in it say how far above
    /// that edge each of the chain's copies sits, so the copies with no row
    /// on screen can come down from above the timeline together.
    nonisolated static var quotedMessageChainBottom: NamedCoordinateSpace { .named("quoted-message-chain-bottom") }
}
