import SwiftUI

extension MessagingNetwork {
    /// The fill for the user's own bubbles, after each network's brand color,
    /// muted toward a neutral gray so it doesn't glare. Light mode gets more
    /// muting since saturated fills look harshest against a white timeline.
    func outgoingBubbleColor(for colorScheme: ColorScheme) -> Color {
        let muting = colorScheme == .dark ? 0.15 : 0.3
        return brandColor.mix(with: Color(white: 0.55), by: muting)
    }

    /// Each network's brand color, deepened where needed so white message text stays legible.
    private var brandColor: Color {
        switch self {
        case .whatsApp: Color(red: 0.08, green: 0.62, blue: 0.36)
        case .telegram: Color(red: 0.16, green: 0.6, blue: 0.86)
        case .signal: Color(red: 0.23, green: 0.46, blue: 0.94)
        case .iMessage: .blue
        case .googleMessages: Color(red: 0.1, green: 0.45, blue: 0.91)
        case .googleVoice: Color(red: 0.09, green: 0.5, blue: 0.22)
        case .discord: Color(red: 0.35, green: 0.4, blue: 0.95)
        // A softer plum than Slack's deep aubergine, which reads harsh as a bubble.
        case .slack: Color(red: 0.5, green: 0.3, blue: 0.55)
        case .instagram: Color(red: 0.6, green: 0.2, blue: 0.85)
        case .facebook: Color(red: 0.0, green: 0.47, blue: 1.0)
        case .linkedIn: Color(red: 0.04, green: 0.4, blue: 0.76)
        case .twitter: Color(red: 0.11, green: 0.61, blue: 0.94)
        case .beeper, .other: .accentColor
        }
    }
}
