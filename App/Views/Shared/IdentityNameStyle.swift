import SwiftUI

/// A person's name colour, resolved for the appearance it's drawn in: the
/// deeper shade on a light background, the brighter one on a dark one.
struct IdentityNameStyle: ShapeStyle {
    let color: IdentityColor

    func resolve(in environment: EnvironmentValues) -> Color {
        environment.colorScheme == .dark ? color.darkName : color.lightName
    }
}
