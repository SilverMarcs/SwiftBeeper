import SwiftUI

struct ComposerDictationButton: View {
    let composer: Composer
    var isInline = false
    @ScaledMetric(relativeTo: .body) private var symbolSize = 20
    @Environment(DictationSettings.self) private var settings
    @Environment(InputManager.self) private var input

    private var idleColor: Color {
        #if os(iOS)
        .secondary
        #else
        isInline ? .secondary : .primary
        #endif
    }

    /// Dictation is shared; only the composer it writes into shows it.
    private var isRecording: Bool {
        input.dictationTarget == composer.target && input.dictation.isRecording
    }

    private var isBusy: Bool {
        input.dictationTarget == composer.target && input.dictation.isBusy
    }

    var body: some View {
        if settings.isEnabled {
            Button {
                input.toggleDictation(in: composer, using: settings)
            } label: {
                // Use the field's natural line height so this control cannot
                // make the single-line composer taller, including while busy.
                Text("M")
                    .hidden()
                    .accessibilityHidden(true)
                    .overlay {
                        Group {
                            if isBusy {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    #if os(macOS)
                                    .controlSize(.mini)
                                    #endif
                            } else {
                                Label(isRecording ? "Finish Dictation" : "Dictate", systemImage: "waveform")
                                    .labelStyle(.iconOnly)
                                    .imageScale(.small)
                            }
                        }
                    }
                    .frame(width: symbolSize, height: isInline ? nil : symbolSize)
                .foregroundStyle(isRecording ? Color.accentColor : idleColor)
                #if os(macOS)
                .frame(width: isInline ? 36 : nil)
                #else
                .frame(width: isInline ? 44 : nil)
                #endif
                .padding(.vertical, isInline ? 8 : 0)
                .contentShape(.rect)
            }
            .tint(isRecording ? Color.accentColor : idleColor)
            // One dictation at a time, in the composer that started it.
            .disabled(isBusy || input.isSubmittingDictation
                || (input.dictation.isActive && input.dictationTarget != composer.target))
            .accessibilityLabel(isBusy ? "Transcribing" : isRecording ? "Finish Dictation" : "Dictate")
            .accessibilityValue(isRecording ? "Recording" : isBusy ? "Processing" : "Ready")
            .help(isRecording ? "Finish dictation and transcribe" : "Dictate a message")
        }
    }
}
