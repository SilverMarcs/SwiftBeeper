import SwiftUI

/// A Markdown heading, a step or two above the body text.
struct MessageHeadingView: View {
    let level: Int
    let text: AttributedString

    var body: some View {
        Text(text)
            .font(font)
            .bold()
    }

    private var font: Font {
        switch level {
        case 1: .title3
        case 2: .headline
        default: .body
        }
    }
}
