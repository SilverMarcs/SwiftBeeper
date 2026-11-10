import SwiftUI

/// A fenced code block: monospaced, verbatim, on a subtle fill.
struct MessageCodeBlockView: View {
    let code: String

    var body: some View {
        Text(verbatim: code)
            .font(.callout.monospaced())
            .padding(8)
            .background(.quinary, in: .rect(cornerRadius: 6))
    }
}
