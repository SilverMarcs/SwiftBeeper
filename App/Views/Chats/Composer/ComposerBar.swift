#if os(iOS)
import SwiftUI

/// The composer on iPhone and iPad, along the bottom edge above the keyboard,
/// for a chat or a thread. macOS uses `MessageInputView`.
///
/// It looks like the system bottom bar it replaced: the attachment button's
/// circle beside a field with dictation inside its end. Focusing it keeps the
/// one row, reaching nearer the edges as a focused search field does, and the
/// field grows upwards with the draft, a line at a time, while the buttons
/// stay on its bottom line. Once there's something to send, Send takes
/// dictation's place at the field's end.
struct ComposerBar: View {
    @Environment(InputManager.self) private var input
    @Environment(ChatStore.self) private var chatStore
    @Environment(DictationSettings.self) private var dictationSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let composer: Composer
    let chat: Chat
    /// The conversation's failure, shown above the field.
    let error: String?

    /// Whether the editor has focus. It follows the editor rather than the
    /// request for focus, so the composer only starts to grow or shrink
    /// once UIKit has announced the keyboard moving with it.
    @State private var isEditing = false
    @State private var width: CGFloat = 0
    /// Where a sent bubble flies from.
    @State private var editorFrame: CGRect?

    /// Bumped each time the bar asks the editor for focus, so it asks again
    /// even when the composer already thinks it has focus.
    @State private var focusAttempt = 0

    private var editorHeight: CGFloat {
        guard isEditing, width > 0 else { return ComposerBarLayout.rowHeight }
        let editorWidth = ComposerBarLayout.editorWidth(in: width, isFocused: true)
        return ComposerEditor.fittingHeight(of: composer.text, width: editorWidth, maximumLines: ComposerTextView.maximumLines)
    }

    /// Send has the field's end once there's something to send, and while
    /// an edit saves. A recording keeps dictation there until it has become
    /// text, so it can be finished.
    private var showsSend: Bool {
        composer.isSavingEdit || (composer.hasContent && !input.isDictating(in: composer))
    }

    var body: some View {
        VStack(spacing: 0) {
            // What the message carries sits above the composer.
            if let error {
                ComposerErrorBanner(message: error)
                    .clipShape(.rect(cornerRadius: 12))
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            MessagePendingAttachmentsBar(composer: composer)
            if composer.target.isThread && !composer.isEditing && chatStore.repliesInThreads(in: chat) {
                AlsoSendToChatToggle(isOn: Bindable(composer).alsoSendToChat, chat: chat)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }

            ZStack {
                GlassEffectContainer(spacing: 0) {
                    ComposerBarLayout(isFocused: isEditing, editorHeight: editorHeight) {
                        Color.clear
                            .glassEffect(.regular, in: .rect(cornerRadius: ComposerBarLayout.cornerRadius))
                            .composerBarPart(.panel)

                        ComposerBarAttachButton(composer: composer)
                            .composerBarPart(.attach)
                    }
                }

                // The container draws its glass over everything inside it that
                // isn't glass itself, so the field's contents are laid over it
                // by an identical layout, with empty stand-ins for the buttons.
                ComposerBarLayout(isFocused: isEditing, editorHeight: editorHeight) {
                    Color.clear.composerBarPart(.attach)

                    ComposerTextView(
                        text: Bindable(composer).text,
                        isFocused: Bindable(composer).isFocused,
                        isEditing: $isEditing,
                        focusAttempt: focusAttempt,
                        selection: composer.selection,
                        mentions: composer.draft.mentions.map(\.range),
                        placeholder: composer.prompt,
                        onSelectionChange: { composer.selection = $0 },
                        onReturn: send
                    )
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { editorFrame = $0 }
                    .composerBarPart(.editor)

                    if dictationSettings.isEnabled {
                        ComposerDictationButton(composer: composer, isInline: true, symbolScale: .large)
                            .buttonStyle(.plain)
                            .opacity(showsSend ? 0 : 1)
                            .scaleEffect(showsSend ? 0.5 : 1)
                            .allowsHitTesting(!showsSend)
                            .accessibilityHidden(showsSend)
                            .composerBarPart(.dictation)
                    }

                    ComposerBarSendButton(
                        isEditing: composer.isEditing,
                        isSaving: composer.isSavingEdit,
                        isEnabled: input.canSubmit(composer),
                        send: send
                    )
                    .opacity(showsSend ? 1 : 0)
                    .scaleEffect(showsSend ? 1 : 0.5)
                    .allowsHitTesting(showsSend)
                    .accessibilityHidden(!showsSend)
                    .composerBarPart(.send)
                }
            }
        }
        // At rest the bar sits a little into the home indicator's margin, as
        // the system bottom bar does; above the keyboard it keeps clear.
        .padding(.bottom, isEditing ? ComposerBarLayout.focusedMargin : -6)
        // The system bottom bar kept the timeline this much further above
        // its items.
        .padding(.top, 10)
        // Its top edge is where the timeline's safe area ends.
        .background(ComposerKeyboardAnchor())
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.4, extraBounce: 0.05), value: isEditing)
        // Each line the draft gains or loses grows or shrinks the field
        // smoothly, and the timeline follows it.
        .animation(.smooth(duration: 0.25), value: editorHeight)
        .animation(.smooth(duration: 0.2), value: showsSend)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // Another conversation's composer can take over the bar, as when iPad
        // switches chats with the keyboard up.
        .onChange(of: composer.target) { oldTarget, _ in
            input.composer(for: oldTarget).isFocused = false
            composer.isFocused = isEditing
        }
        // Reply, Edit, and notification drafts ask for focus. Reply and Edit
        // often come from a context menu, which restores the keyboard state
        // from before it opened as it finishes dismissing, resigning an
        // editor focused before then. The dismissal takes longer on some
        // devices and menus than others, so focus is asked for again until it
        // has held past it. A thread's composer appears after its Reply, so
        // this also runs for a request made before it existed.
        .task(id: composer.focusRequestID) {
            guard composer.focusRequestID != nil else { return }
            do {
                try await Task.sleep(for: InputManager.contextMenuDismissalDelay)
                for _ in 0..<Self.focusAttempts {
                    if !isEditing {
                        composer.isFocused = true
                        focusAttempt += 1
                    }
                    try await Task.sleep(for: .milliseconds(150))
                }
            } catch {
                return
            }
            composer.didHandleFocusRequest()
        }
        // Leaving the chat can tear the editor down while it still has focus;
        // the next chat's first focus must register as a change.
        .onDisappear {
            composer.isFocused = false
        }
        // Outermost, so folding away takes the whole bar out of the safe area.
        .yieldsKeyboardToOtherFields(composer)
    }

    /// How many times a focus request checks that the editor has focus.
    private static let focusAttempts = 4

    /// Sends or saves the draft, keeping the keyboard up for the next message.
    private func send() {
        input.submit(composer, sourceFrame: editorFrame)
    }
}
#endif
