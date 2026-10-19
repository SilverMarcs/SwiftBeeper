#if os(macOS)
import AppKit

@MainActor
final class MacActionMenuItem: NSMenuItem {
    private var handler: (@MainActor () -> Void)? = nil

    convenience init(_ action: RelayAction) {
        self.init(title: action.title, action: nil, keyEquivalent: "")
        handler = action.perform
        target = self
        self.action = #selector(invoke)
        image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
        state = action.selected ? .on : .off
    }

    nonisolated override init(title: String, action: Selector?, keyEquivalent: String) { super.init(title: title, action: action, keyEquivalent: keyEquivalent) }
    nonisolated required init(coder: NSCoder) { super.init(coder: coder) }
    @objc private func invoke() { handler?() }
}

#endif
