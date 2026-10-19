#if os(macOS)
import AppKit

extension NSView {
    func pinEdges(to parent: NSView, inset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
        ])
    }
}

extension NSStackView {
    convenience init(vertical views: [NSView], spacing: CGFloat = 8) {
        self.init(views: views)
        orientation = .vertical
        alignment = .leading
        self.spacing = spacing
    }
}
#endif
