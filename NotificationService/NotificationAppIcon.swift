import Foundation
@preconcurrency import Intents

/// Uses the containing app's existing icon when a group has no picture.
enum NotificationAppIcon {
    nonisolated static func image() -> INImage? {
        var appURL = Bundle.main.bundleURL
        while appURL.pathExtension != "app", appURL.path != "/" {
            appURL.deleteLastPathComponent()
        }
        guard let appBundle = Bundle(url: appURL),
              let resources = appBundle.resourceURL else { return nil }

        let icons = appBundle.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let iconFiles = primary?["CFBundleIconFiles"] as? [String]
        guard let iconFile = iconFiles?.last
            ?? (appBundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String) else { return nil }
        let iconName = URL(filePath: iconFile).deletingPathExtension().lastPathComponent
        let files = (try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)) ?? []
        guard let iconURL = files.first(where: {
            $0.deletingPathExtension().lastPathComponent == iconName
                || $0.lastPathComponent.hasPrefix(iconName + "@")
        }) else { return nil }
        return INImage(url: iconURL)
    }
}
