import SwiftUI

extension View {
    /// Vertical padding around a bubble row. Consecutive rows from one sender sit
    /// 4pt apart; where the sender changes the gap doubles to 8pt, so each side's
    /// run reads as its own block.
    func timelineRowPadding(startsSenderRun: Bool) -> some View {
        padding(.top, startsSenderRun ? 6 : 2)
            .padding(.bottom, 2)
    }
}
