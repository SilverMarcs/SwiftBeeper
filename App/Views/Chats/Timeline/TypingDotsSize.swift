/// How big the typing dots are drawn: full size in a timeline bubble, or
/// compact in a chat row's one-line preview bubble.
enum TypingDotsSize {
    case regular
    case compact

    /// Each dot's diameter, before Dynamic Type scaling.
    var diameter: Double {
        switch self {
        case .regular: 7
        case .compact: 4
        }
    }

    /// The gap between dots, before Dynamic Type scaling.
    var spacing: Double {
        switch self {
        case .regular: 4
        case .compact: 2.5
        }
    }
}
