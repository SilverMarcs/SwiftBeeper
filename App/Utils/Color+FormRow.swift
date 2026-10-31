import SwiftUI

extension ShapeStyle where Self == Color {
    /// The fill of a grouped `Form` row, for custom views that sit beside one.
    /// SwiftUI has no semantic equivalent, and it changes in dark mode and sheets.
    static var formRowBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .quinarySystemFill)
        #endif
    }
}
