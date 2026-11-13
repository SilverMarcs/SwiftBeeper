import SwiftUI

/// A person's colour, as in Messages and Telegram: the fill of their initials
/// avatar and, in groups, the colour of their name above their messages.
///
/// The colour comes from a fixed FNV-1a hash of a stable ID — a Matrix user
/// ID, or a chat ID for a chat's own initials — so it survives relaunches and
/// display-name changes and matches between avatar and name. Never Swift's
/// `Hasher`, which is seeded afresh on every launch.
struct IdentityColor: Equatable, Sendable {
    /// The avatar gradient's lighter top.
    let avatarTop: Color
    /// The avatar gradient's deeper bottom, which white initials sit on.
    let avatarBottom: Color
    /// The name on a light timeline: deep enough to read on white.
    let lightName: Color
    /// The name on a dark timeline: bright enough to read on black.
    let darkName: Color

    /// The palette entry `id` hashes to.
    init(id: String) {
        self = Self.palette[Int(Self.stableHash(of: id) % UInt64(Self.palette.count))]
    }

    private init(avatarTop: Color, avatarBottom: Color, lightName: Color, darkName: Color) {
        self.avatarTop = avatarTop
        self.avatarBottom = avatarBottom
        self.lightName = lightName
        self.darkName = darkName
    }

    /// The initials avatar's fill, lighter at the top.
    var avatarGradient: LinearGradient {
        LinearGradient(colors: [avatarTop, avatarBottom], startPoint: .top, endPoint: .bottom)
    }

    /// The name's colour, tuned for the current light or dark appearance.
    var nameStyle: IdentityNameStyle {
        IdentityNameStyle(color: self)
    }

    /// 64-bit FNV-1a over the UTF-8 bytes: the same on every launch and device.
    static func stableHash(of string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// Ten hues spread around the wheel. Avatars keep one gradient in both
    /// appearances; names take a deeper shade on light and a brighter one on
    /// dark, so warm hues such as amber stay legible as text. Reordering or
    /// resizing the palette recolours everyone, so append with care.
    private static let palette: [IdentityColor] = [
        // Red
        .init(rgb: (0.98, 0.45, 0.42), (0.86, 0.24, 0.24), (0.76, 0.16, 0.16), (1.00, 0.47, 0.45)),
        // Orange
        .init(rgb: (1.00, 0.62, 0.32), (0.92, 0.43, 0.10), (0.70, 0.32, 0.00), (1.00, 0.62, 0.32)),
        // Amber
        .init(rgb: (0.96, 0.72, 0.26), (0.84, 0.54, 0.04), (0.56, 0.40, 0.00), (0.96, 0.76, 0.32)),
        // Green
        .init(rgb: (0.42, 0.80, 0.46), (0.18, 0.60, 0.30), (0.10, 0.50, 0.22), (0.42, 0.82, 0.50)),
        // Teal
        .init(rgb: (0.32, 0.78, 0.78), (0.06, 0.56, 0.60), (0.00, 0.46, 0.50), (0.36, 0.82, 0.82)),
        // Blue
        .init(rgb: (0.40, 0.72, 1.00), (0.14, 0.48, 0.90), (0.08, 0.40, 0.78), (0.46, 0.72, 1.00)),
        // Indigo
        .init(rgb: (0.54, 0.56, 1.00), (0.34, 0.33, 0.88), (0.34, 0.32, 0.84), (0.62, 0.64, 1.00)),
        // Purple
        .init(rgb: (0.76, 0.52, 0.98), (0.54, 0.30, 0.84), (0.52, 0.24, 0.76), (0.78, 0.56, 1.00)),
        // Pink
        .init(rgb: (1.00, 0.50, 0.72), (0.86, 0.26, 0.52), (0.76, 0.14, 0.42), (1.00, 0.54, 0.74)),
        // Cocoa
        .init(rgb: (0.78, 0.61, 0.48), (0.58, 0.41, 0.30), (0.50, 0.33, 0.20), (0.84, 0.66, 0.52)),
    ]

    /// An entry from sRGB components: avatar top and bottom, then the name
    /// on light and on dark.
    private init(
        rgb avatarTop: (Double, Double, Double),
        _ avatarBottom: (Double, Double, Double),
        _ lightName: (Double, Double, Double),
        _ darkName: (Double, Double, Double)
    ) {
        func color(_ rgb: (Double, Double, Double)) -> Color {
            Color(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2)
        }
        self.init(
            avatarTop: color(avatarTop),
            avatarBottom: color(avatarBottom),
            lightName: color(lightName),
            darkName: color(darkName)
        )
    }
}
