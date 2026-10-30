import Intents
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
typealias PlatformViewController = NSViewController
#else
typealias PlatformViewController = UIViewController
#endif

/// The extension's principal class, which only hosts `ShareView` and reports
/// back to the share sheet.
final class ShareViewController: PlatformViewController {
    #if os(macOS)
    override func loadView() {
        view = NSHostingView(rootView: ShareView(model: makeModel()))
        preferredContentSize = NSSize(width: 420, height: 560)
    }
    #else
    override func viewDidLoad() {
        super.viewDidLoad()
        // Swiping the sheet away would skip handing the store back to the app.
        isModalInPresentation = true
        let host = UIHostingController(rootView: ShareView(model: makeModel()))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
    #endif

    /// The conversation picked from the share sheet's suggestions row.
    private var suggestedChatID: String? {
        #if os(iOS)
        (extensionContext?.intent as? INSendMessageIntent)?.conversationIdentifier
        #else
        nil
        #endif
    }

    private func makeModel() -> ShareModel {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        return ShareModel(
            providers: items.flatMap { $0.attachments ?? [] },
            suggestedChatID: suggestedChatID,
            complete: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            cancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            }
        )
    }
}
