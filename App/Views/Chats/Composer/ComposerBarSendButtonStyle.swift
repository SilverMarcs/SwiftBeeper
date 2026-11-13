#if os(iOS)
import SwiftUI

/// The composer bar's Send button: a white symbol on a solid accent circle,
/// or a spinner while an edit saves.
struct ComposerBarSendButtonStyle: ButtonStyle {
    let diameter: CGFloat
    var isBusy = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.body)
            .bold()
            .foregroundStyle(.white)
            .opacity(isBusy ? 0 : 1)
            .overlay {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
            .frame(width: diameter, height: diameter)
            .background(Color.accentColor, in: .circle)
            .contentShape(.circle)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
#endif
