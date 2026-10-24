import SwiftUI

/// A selectable label/value row for the chat info and profile sheets.
struct InfoRow: View {
    let label: String
    let value: String
    let monospaced: Bool

    init(_ label: String, value: String, monospaced: Bool = false) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
    }

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .foregroundStyle(.secondary)
                .font(monospaced ? .caption.monospaced() : nil)
                .textSelection(.enabled)
        }
    }
}
