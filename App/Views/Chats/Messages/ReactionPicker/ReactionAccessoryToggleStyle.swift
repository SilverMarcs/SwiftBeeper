#if os(iOS)
import SwiftUI

struct ReactionAccessoryToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .frame(minWidth: 44, minHeight: 44)
                .overlay(alignment: .bottom) {
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
        }
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}
#endif
