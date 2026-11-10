import SwiftUI

/// Shown over the poster of a video too large to download for the bubble.
struct VideoTooLargeLabel: View {
    let fileSize: Int?

    var body: some View {
        VStack {
            Label("Video Too Large to Play", systemImage: "film")
                .font(.subheadline)
                .bold()
            if let fileSize {
                Text(Int64(fileSize).formatted(.byteCount(style: .file)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .padding()
        .accessibilityElement(children: .combine)
    }
}
