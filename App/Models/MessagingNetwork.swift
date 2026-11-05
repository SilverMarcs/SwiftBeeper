import Foundation

/// The chat network a bridged account belongs to, parsed from its account ID.
enum MessagingNetwork: Equatable {
    case beeper
    case whatsApp
    case telegram
    case signal
    case iMessage
    case googleMessages
    case googleVoice
    case discord
    case slack
    case instagram
    case facebook
    case linkedIn
    case twitter
    case other

    /// Account IDs are bridge IDs such as "whatsapp", "local-telegram", or
    /// "discordgo"; the Beeper Matrix account itself is "hungryserv".
    init(accountID: String?) {
        guard let accountID else {
            self = .other
            return
        }
        var bridgeID = accountID.lowercased()
        if bridgeID.hasPrefix("local-") { bridgeID.removeFirst("local-".count) }

        switch bridgeID {
        case "hungryserv", "matrix": self = .beeper
        case "whatsapp": self = .whatsApp
        case "telegram": self = .telegram
        case "signal": self = .signal
        case "imessage", "imessagecloud", "imessagego": self = .iMessage
        case "gmessages": self = .googleMessages
        case "gvoice": self = .googleVoice
        case "discord", "discordgo": self = .discord
        case "slack", "slackgo": self = .slack
        case "instagram", "instagramgo": self = .instagram
        case "facebook", "facebookgo", "messenger": self = .facebook
        case "linkedin": self = .linkedIn
        case "twitter": self = .twitter
        default: self = .other
        }
    }
}
