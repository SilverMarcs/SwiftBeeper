import SwiftUI

/// Keeps a recording tied to the composer that started it and its reply or
/// edit, and reports its failures there.
struct ComposerDictationLifecycle: ViewModifier {
    @Environment(InputManager.self) private var input
    @Environment(DictationSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    let composer: Composer

    func body(content: Content) -> some View {
        let ownsDictation = input.dictationTarget == composer.target
        content
            #if os(iOS)
            .sensoryFeedback(trigger: input.dictationFeedback) { _, event in
                input.dictationTarget == composer.target ? Self.feedback(for: event) : nil
            }
            .sensoryFeedback(.error, trigger: input.dictation.error) { _, error in
                input.dictationTarget == composer.target && error != nil
            }
            #endif
            .onChange(of: composer.target) { oldTarget, _ in
                if input.dictationTarget == oldTarget { input.dictation.cancel() }
            }
            .onChange(of: composer.activeMessage?.id) { input.cancelDictation(for: composer) }
            .onChange(of: settings.isEnabled) {
                if !settings.isEnabled { input.cancelDictation(for: composer) }
            }
            .onChange(of: scenePhase) {
                if scenePhase == .background { input.cancelDictation(for: composer) }
            }
            .onDisappear { input.cancelDictation(for: composer) }
            .alert("Couldn’t Dictate", isPresented: Binding(
                get: { ownsDictation && input.dictation.error != nil },
                set: { if !$0 { input.dictation.error = nil } }
            )) {
                Button("OK") { input.dictation.error = nil }
            } message: {
                Text(input.dictation.error ?? "")
            }
    }

    #if os(iOS)
    private static func feedback(for event: DictationFeedback?) -> SensoryFeedback? {
        switch event?.kind {
        case .recordingStarted, .transcriptReady: .impact(weight: .light, intensity: 0.8)
        case .send: .impact(weight: .medium, intensity: 0.7)
        case nil: nil
        }
    }
    #endif
}
