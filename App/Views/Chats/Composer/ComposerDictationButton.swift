import SwiftUI

struct ComposerDictationButton: View {
    var isInline = false
    @ScaledMetric(relativeTo: .body) private var symbolSize = 20
    @Environment(DictationSettings.self) private var settings
    @Environment(InputManager.self) private var input

    var body: some View {
        if settings.isEnabled {
            Button {
                input.toggleDictation(using: settings)
            } label: {
                Group {
                    if input.dictation.isBusy {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Label(input.dictation.isRecording ? "Finish Dictation" : "Dictate", systemImage: "waveform")
                            .labelStyle(.iconOnly)
                            .imageScale(.small)
                    }
                }
                .frame(width: symbolSize, height: symbolSize)
                .foregroundStyle(input.dictation.isRecording ? Color.accentColor : Color.secondary)
                .frame(width: isInline ? 44 : nil)
                .padding(.vertical, isInline ? 8 : 0)
                .contentShape(.rect)
            }
            .tint(input.dictation.isRecording ? Color.accentColor : Color.secondary)
            .disabled(input.dictation.isBusy || input.isSubmittingDictation)
            .accessibilityLabel(input.dictation.isBusy ? "Transcribing" : input.dictation.isRecording ? "Finish Dictation" : "Dictate")
            .accessibilityValue(input.dictation.isRecording ? "Recording" : input.dictation.isBusy ? "Processing" : "Ready")
            .help(input.dictation.isRecording ? "Finish dictation and transcribe" : "Dictate a message")
        }
    }
}
