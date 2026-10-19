#if os(macOS)
import AppKit

@MainActor
final class MacActionButton: NSButton {
    var actionHandler: (() -> Void)?

    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); imagePosition = .imageOnly }
        bezelStyle = .rounded
        target = self
        self.action = #selector(invoke)
        actionHandler = action
    }

    required init?(coder: NSCoder) { nil }
    @objc private func invoke() { actionHandler?() }
}

#endif
