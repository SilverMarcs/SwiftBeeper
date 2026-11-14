import SwiftUI

extension View {
    /// Vertical padding around a bubble row. Consecutive rows from one sender sit
    /// 4pt apart; where the sender changes the gap doubles to 8pt, so each side's
    /// run reads as its own block.
    func timelineRowPadding(startsSenderRun: Bool) -> some View {
        timelineRowTopPadding(startsSenderRun: startsSenderRun)
            .padding(.bottom, 2)
    }

    /// The part of `timelineRowPadding(startsSenderRun:)` above a row, for
    /// where a row starts without ending, as a reply does below the quoted
    /// messages shown above its bubble.
    func timelineRowTopPadding(startsSenderRun: Bool) -> some View {
        padding(.top, startsSenderRun ? 6 : 2)
    }
}
