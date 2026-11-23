import SwiftUI

/// Segments for all reactions and then each reaction, most reacted first,
/// filtering the reaction details sheet.
struct ReactionDetailsFilterPicker: View {
    @Environment(\.displayScale) private var displayScale

    let groups: [GroupedReaction]
    /// The reaction shown, or nil for all of them.
    @Binding var selection: ReactionAppearance?
    /// The room the toolbar leaves beside its close button. A toolbar item
    /// is offered next to none, so the picker can't size itself to it. Nil
    /// leaves the picker at its natural width.
    let maxWidth: CGFloat?

    /// The pills' custom emoji size, so their decoded frames are reused.
    @ScaledMetric(relativeTo: .subheadline) private var emojiDimension = ReactionGlyph.imageDimension(for: .subheadline)
    /// Custom emoji images by source. A segment takes a finished image, so
    /// it can't load one itself the way a view can.
    @State private var emojiImages: [String: CGImage] = [:]

    var body: some View {
        // Each reaction with its count while they fit, then without counts,
        // then only the most reacted; the rest are still listed under All.
        // A squeezed segmented picker truncates every label to "…", and one
        // too wide makes the toolbar fold it and the close button into an
        // overflow menu. Long-pressing a pill always selects one of the
        // first few, since a message shows at most `ReactionPill.visibleLimit`.
        ViewThatFits(in: .horizontal) {
            picker(groups, showsCounts: true)
            ForEach((1...max(groups.count, 1)).reversed(), id: \.self) { limit in
                picker(Array(groups.prefix(limit)), showsCounts: false)
            }
        }
        .frame(width: maxWidth, alignment: .leading)
        .task(id: emojiPixelSize) { await loadEmojiImages() }
    }

    private func picker(_ groups: [GroupedReaction], showsCounts: Bool) -> some View {
        Picker("Reaction", selection: $selection) {
            Text("All")
                .tag(ReactionAppearance?.none)
            ForEach(groups) { group in
                segment(for: group, showsCount: showsCounts)
                    .accessibilityLabel("\(group.spokenName), \(group.count)")
                    .tag(Optional(group.appearance))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    /// An emoji with its count, or a custom emoji's image or the dashed face
    /// alone: a segment shows an image or text, not both.
    @ViewBuilder
    private func segment(for group: GroupedReaction, showsCount: Bool) -> some View {
        switch group.appearance {
        case .emoji(let emoji):
            Text(showsCount ? "\(emoji) \(group.count)" : emoji)
        case .customEmoji(let source):
            if let image = emojiImages[source] ?? CustomEmojiFrames.cached(source, pixelSize: emojiPixelSize)?.images.first {
                Image(decorative: image, scale: displayScale)
                    .renderingMode(.original)
            } else {
                Text(group.spokenName)
            }
        case .unrecognized:
            Image(systemName: "face.dashed")
        }
    }

    private var emojiPixelSize: Int {
        CustomEmojiImage.pixelSize(for: emojiDimension, scale: displayScale)
    }

    private func loadEmojiImages() async {
        for group in groups {
            guard case .customEmoji(let source) = group.appearance, emojiImages[source] == nil,
                  let image = await CustomEmojiFrames.load(source, pixelSize: emojiPixelSize)?.images.first
            else { continue }
            emojiImages[source] = image
        }
    }
}
