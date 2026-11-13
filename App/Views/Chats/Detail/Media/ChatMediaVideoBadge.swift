import SwiftUI

/// Marks a grid tile as a video, with its length when known.
struct ChatMediaVideoBadge: View {
    let duration: Double?

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "video.fill")
            if let duration, duration >= 1 {
                Text(Duration.seconds(duration), format: .time(pattern: .minuteSecond))
                    .monospacedDigit()
            }
        }
        .font(.caption2)
        .bold()
        .foregroundStyle(.white)
        .shadow(radius: 2)
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                .frame(maxHeight: 28)
        }
        .accessibilityHidden(true)
    }
}
