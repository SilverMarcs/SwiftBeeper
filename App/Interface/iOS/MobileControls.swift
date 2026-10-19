#if os(iOS)
import UIKit

extension UIView {
    func pinEdges(to parent: UIView, inset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset), trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            topAnchor.constraint(equalTo: parent.topAnchor, constant: inset), bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
        ])
    }
}
extension UIStackView {
    convenience init(vertical views: [UIView], spacing: CGFloat = 8) {
        self.init(arrangedSubviews: views); axis = .vertical; self.spacing = spacing
    }
}
extension RelayAction {
    @MainActor var uiAction: UIAction {
        UIAction(title: title, image: UIImage(systemName: symbol), attributes: destructive ? .destructive : [], state: selected ? .on : .off) { _ in perform() }
    }
}
#endif
