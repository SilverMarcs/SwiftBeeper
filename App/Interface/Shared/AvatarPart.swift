import Foundation

struct AvatarPart: Equatable {
    let name: String
    let source: String?
    let size: CGFloat
    let x: CGFloat
    let y: CGFloat

    static func group(for chat: Chat) -> [Self] {
        let others = chat.participants?.items.filter { $0.isSelf != true } ?? []
        let participants = others.isEmpty ? (chat.participants?.items ?? []) : others
        var sources = participants.prefix(4).map { ($0.displayName, $0.imgURL) }
        if sources.isEmpty { sources = [(chat.displayTitle, nil), ("Group", nil)] }
        else if sources.count == 1 { sources.append((chat.displayTitle, nil)) }
        let positions: [(CGFloat, CGFloat, CGFloat)]
        switch sources.count {
        case 2: positions = [(0.56, -0.16, -0.08), (0.56, 0.16, 0.12)]
        case 3: positions = [(0.46, -0.17, -0.16), (0.42, 0.18, -0.04), (0.44, -0.02, 0.2)]
        default: positions = [(0.4, -0.18, -0.16), (0.38, 0.19, -0.08), (0.38, -0.16, 0.18), (0.36, 0.17, 0.2)]
        }
        return zip(sources, positions).map { source, position in Self(name: source.0, source: source.1, size: position.0, x: position.1, y: position.2) }
    }
}
