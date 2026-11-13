#if os(iOS)
import SwiftUI

/// The part of the composer bar a subview plays, which places it.
nonisolated enum ComposerBarPart {
    /// The field's glass, which grows with the draft.
    case panel
    case attach
    /// Leaves a reply or edit.
    case cancel
    case editor
    case dictation
    case send
}

private nonisolated struct ComposerBarPartKey: LayoutValueKey {
    static let defaultValue = ComposerBarPart.panel
}

extension View {
    func composerBarPart(_ part: ComposerBarPart) -> some View {
        layoutValue(key: ComposerBarPartKey.self, value: part)
    }
}

extension LayoutSubview {
    var composerBarPart: ComposerBarPart { self[ComposerBarPartKey.self] }
}
#endif
