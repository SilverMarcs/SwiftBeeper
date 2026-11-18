import SwiftUI

struct TypingDotsPhaseView: View {
    let highlightedDot: Int?
    @ScaledMetric private var diameter: Double
    @ScaledMetric private var spacing: Double

    init(highlightedDot: Int?, size: TypingDotsSize) {
        self.highlightedDot = highlightedDot
        _diameter = ScaledMetric(wrappedValue: size.diameter, relativeTo: .body)
        _spacing = ScaledMetric(wrappedValue: size.spacing, relativeTo: .body)
    }

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
