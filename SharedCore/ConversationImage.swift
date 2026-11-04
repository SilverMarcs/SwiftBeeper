import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The picture donated with a conversation for the share sheet's suggestions.
/// The system draws an empty circle for a conversation without one, so a chat
/// without a photo gets Relay's icon, as group notifications do. Image bytes,
/// since the system keeps them with the donation rather than reading a file
/// later.
nonisolated enum ConversationImage {
    /// Pixels per side: the share sheet shows about 60pt at 3x.
    private static let pixelSize = 192

    /// - Parameter photo: The conversation's Matrix avatar source, if any.
    static func make(photo: String?) async -> Data? {
        if let photo, !photo.isEmpty,
           let file = try? await MatrixRuntime.shared.localAsset(photo),
           let image = ImageThumbnail.make(contentsOf: file, maximumPixelSize: pixelSize),
           let data = png(image) {
            return data
        }
        return appIcon()
    }

    /// The containing app's icon file, found from its Info.plist.
    private static func appIcon() -> Data? {
        var appURL = Bundle.main.bundleURL
        while appURL.pathExtension != "app", appURL.path != "/" {
            appURL.deleteLastPathComponent()
        }
        guard let appBundle = Bundle(url: appURL), let resources = appBundle.resourceURL else { return nil }
        let icons = appBundle.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        guard let iconFile = (primary?["CFBundleIconFiles"] as? [String])?.last
            ?? (appBundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String) else { return nil }
        let iconName = URL(filePath: iconFile).deletingPathExtension().lastPathComponent
        let files = (try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)) ?? []
        guard let iconURL = files.first(where: {
            $0.deletingPathExtension().lastPathComponent == iconName || $0.lastPathComponent.hasPrefix(iconName + "@")
        }) else { return nil }
        return try? Data(contentsOf: iconURL)
    }

    private static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
