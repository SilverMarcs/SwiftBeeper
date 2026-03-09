import SwiftUI

enum ChatVisualStyle {
    static func bubbleFill(isOutgoing: Bool) -> AnyShapeStyle {
        if isOutgoing {
            return AnyShapeStyle(Color.accentColor.gradient)
        }
        return AnyShapeStyle(.background.tertiary)
    }

    static func reactionFill(isSelected: Bool) -> AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(.tint.secondary)
        }
        return AnyShapeStyle(.quinary)
    }

    static func replyPreviewFill(isOutgoing: Bool) -> AnyShapeStyle {
        if isOutgoing {
            return AnyShapeStyle(.tint.quaternary)
        }
        return AnyShapeStyle(.quinary)
    }
}
