import CoreGraphics

/// The composer's editor and field, read at the moment a draft is sent so
/// its bubble can grow out of the field with the text where it was typed. A
/// plain reference rather than state: the frames change as the field grows,
/// which nothing needs to redraw for.
@MainActor
final class ComposerSendOrigin {
    #if os(iOS)
    weak var editor: ComposerEditor?
    #else
    weak var editor: MacComposerEditor?
    #endif
    /// The editor's frame in global coordinates.
    var editorFrame: CGRect?
    /// The field's frame, around the editor, in global coordinates.
    var fieldFrame: CGRect?
    let fieldCornerRadius: CGFloat

    init(fieldCornerRadius: CGFloat) {
        self.fieldCornerRadius = fieldCornerRadius
    }

    /// The composer as it shows the draft now.
    func source() -> MessageSendSource? {
        guard let editor, let editorFrame, editorFrame.width > 0, editorFrame.height > 0 else { return nil }
        let text = editor.sendText(in: editorFrame)
        return MessageSendSource(
            fieldFrame: fieldFrame ?? editorFrame,
            fieldCornerRadius: fieldCornerRadius,
            textAnchor: text.anchor,
            anchorsLastLine: text.anchorsLastLine,
            glyphs: text.glyphs
        )
    }
}
