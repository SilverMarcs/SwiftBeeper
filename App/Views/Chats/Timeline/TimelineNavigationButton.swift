import SwiftUI

/// One shortcut, clear of the composer: mentions take priority over latest.
struct TimelineNavigationButton: View {
    let mentions: MentionNavigation?
    let showsLatest: Bool
    let nextMention: () -> Void
    let jumpToLatest: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isMention = mentions?.isVisible == true
        let isBusy = isMention && mentions?.isBusy == true
        let isVisible = isMention || showsLatest
        Group {
            if isVisible {
                Button(action: isMention ? nextMention : jumpToLatest) {
                    Label(isMention ? "Next Mention" : "Jump to Latest", systemImage: isMention ? "at" : "arrow.down")
                        .labelStyle(.iconOnly)
                        .opacity(isBusy ? 0 : 1)
                        .overlay {
                            if isBusy {
                                ProgressView()
                                    .controlSize(.small)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .disabled(isBusy)
                .accessibilityValue(isMention ? "\(mentions?.mentions.count ?? 0) mentions remaining" : "")
                .accessibilityHint(isMention ? mentions?.error ?? "Shows the oldest unread mention of you." : "Shows the latest messages.")
                .help(isMention ? mentions?.error ?? "Go to the next unread mention" : "Jump to Latest")
                .alert("Couldn’t Show Mention", isPresented: Binding(
                    get: { mentions?.alertError != nil },
                    set: { if !$0 { mentions?.dismissError() } }
                )) {
                    Button("OK", role: .cancel) { mentions?.dismissError() }
                } message: {
                    Text(mentions?.alertError ?? "")
                }
                .padding()
                .transition(reduceMotion ? .opacity : .scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.25, bounce: 0.1), value: isVisible)
    }
}
