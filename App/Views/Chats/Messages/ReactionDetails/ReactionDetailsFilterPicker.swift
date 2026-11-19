import SwiftUI

/// Segments for all reactions and then each reaction, most reacted first,
/// filtering the reaction details sheet.
struct ReactionDetailsFilterPicker: View {
    let groups: [GroupedReaction]
    /// The reaction shown, or nil for all of them.
    @Binding var selection: String?
    /// The room the toolbar leaves beside its close button. A toolbar item
    /// is offered next to none, so the picker can't size itself to it. Nil
    /// leaves the picker at its natural width.
    let maxWidth: CGFloat?

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
    }

    private func picker(_ groups: [GroupedReaction], showsCounts: Bool) -> some View {
        Picker("Reaction", selection: $selection) {
            Text("All")
                .tag(String?.none)
            ForEach(groups) { group in
                Text(showsCounts ? "\(group.reactionKey) \(group.count)" : group.reactionKey)
                    .accessibilityLabel("\(group.reactionKey), \(group.count)")
                    .tag(Optional(group.reactionKey))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}
