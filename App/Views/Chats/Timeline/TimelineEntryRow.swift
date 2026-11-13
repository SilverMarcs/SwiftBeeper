import SwiftUI

/// A canonical message with the dividers above it. While the timeline focuses
/// on one message, for a reply, an edit, a reaction or a quote, everything
/// else recedes.
struct TimelineEntryRow: View {
    let entry: TimelineEntry
    let chat: Chat
    let showsUnreadDivider: Bool
    let focusedRowID: Message.ID?
    /// The messages this reply quotes, floated above it while its quote is
    /// shown. Nil otherwise.
    let quotedChain: QuotedMessageChainPresentation?
    /// Whether this message is shown above a reply whose quote was tapped:
    /// its bubble moved there, and the row keeps only its space.
    let quotedChainState: QuotedChainRowState
    @Environment(\.dismissTimelineFocus) private var dismissTimelineFocus

    var body: some View {
        let isIdle = focusedRowID == nil
        let isFocusedRow = focusedRowID == entry.id
        VStack(spacing: 0) {
            if showsUnreadDivider {
                UnreadDividerView()
                    .timelineFocus(isIdle)
                    .padding(.vertical, 4)
            }

            if entry.showsTimestamp {
                TimestampDividerView(timestamp: entry.message.timestamp)
                    .timelineFocus(isIdle)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }

            MessageRowView(entry: entry, chat: chat)
                // Its own quote recedes: what it stands for is shown above.
                .environment(\.recedesReplyPreview, quotedChain?.isPresented == true)
                .timelineFocus(isIdle || isFocusedRow)
                // Under its copy above, which starts over it and ends back
                // over it, so the bubble seems to move: it hides and returns
                // at once. One whose copy only fades fades with it.
                .opacity(quotedChainState.isShownAbove ? 0 : 1)
                .transaction(value: quotedChainState) { transaction in
                    if quotedChainState.moves { transaction.animation = nil }
                }
                .timelineRowPadding(startsSenderRun: entry.startsSenderRun)
                // The swipe actions below take taps across the row's whole
                // width, so the focused row returns to the timeline from the
                // space beside its bubbles itself. VoiceOver has the
                // timeline's own backdrop.
                .background {
                    if isFocusedRow, let dismissTimelineFocus {
                        Button(dismissTimelineFocus.label, action: dismissTimelineFocus.callAsFunction)
                            .buttonStyle(TimelineFocusBackdropStyle(label: dismissTimelineFocus.label))
                            .accessibilityHidden(true)
                    }
                }
                // The dividers above stay put while the message slides.
                .messageSwipeActions(entry.message, in: chat, isEnabled: isIdle)
                // A receded row lets taps through, swipe actions and all, to
                // the timeline's backdrop.
                .allowsHitTesting(isIdle || isFocusedRow)
                // Over the receded rows above, so the reply keeps its place.
                // The zero-height frame stands the chain on the row's top
                // edge, reaching up; an alignment guide in an overlay isn't
                // honoured everywhere and left it covering the reply.
                .overlay(alignment: .top) {
                    if let quotedChain {
                        QuotedMessageChainView(presentation: quotedChain, chat: chat)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(height: 0, alignment: .bottom)
                            // Each tap starts its own chain from the rows.
                            .id(quotedChain.id)
                            // Its messages move and fade by themselves.
                            .transition(.identity)
                    }
                }
        }
    }
}
