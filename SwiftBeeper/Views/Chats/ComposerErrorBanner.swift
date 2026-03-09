import SwiftUI

struct ComposerErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .lineLimit(2)
        }
        .font(.footnote)
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.red.opacity(0.12))
    }
}
