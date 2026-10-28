import SwiftUI

struct TypingDotsPhaseView: View {
    let highlightedDot: Int?
    @ScaledMetric(relativeTo: .body) private var diameter = 4.0
    @ScaledMetric(relativeTo: .body) private var spacing = 3.0

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: diameter, height: diameter)
                    .opacity(highlightedDot == nil || highlightedDot == index ? 1 : 0.45)
                    .scaleEffect(highlightedDot == index ? 1 : 0.85)
            }
        }
    }
}
