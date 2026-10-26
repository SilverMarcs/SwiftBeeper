import SwiftUI

/// Keeps a recording tied to the visible chat and composer action.
struct ComposerDictationLifecycle: ViewModifier {
    @Environment(InputManager.self) private var input
    @Environment(ChatStore.self) private var chats
    @Environment(DictationSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: input.selectedChatID) { input.dictation.cancel() }
            .onChange(of: chats.activeComposerMessage?.id) { input.dictation.cancel() }
            .onChange(of: settings.isEnabled) {
                if !settings.isEnabled { input.dictation.cancel() }
            }
            .onChange(of: scenePhase) {
                if scenePhase == .background { input.dictation.cancel() }
            }
            .onDisappear { input.dictation.cancel() }
            .alert("Couldn’t Dictate", isPresented: Binding(
                get: { input.dictation.error != nil },
                set: { if !$0 { input.dictation.error = nil } }
            )) {
                Button("OK") { input.dictation.error = nil }
            } message: {
                Text(input.dictation.error ?? "")
            }
    }
}
