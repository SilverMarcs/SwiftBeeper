#if os(iOS)
import SwiftUI

/// Finds the UIKit field behind `.searchable` once SwiftUI has installed it, and
/// hands it over with this placeholder view as a coordinate reference.
struct SearchIntrospector: UIViewRepresentable {
    var introspect: (UISearchTextField, UIView) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        introspectAfterLayout(from: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        introspectAfterLayout(from: uiView)
    }

    private func introspectAfterLayout(from view: UIView) {
        Task { @MainActor in
            await Task.yield()
            if let searchField = findSearchTextField(startingFrom: view) {
                introspect(searchField, view)
            }
        }
    }

    private func findSearchTextField(startingFrom view: UIView) -> UISearchTextField? {
        var responder: UIResponder? = view
        while responder != nil {
            if let viewController = responder as? UIViewController {
                if let field = viewController.navigationItem.searchController?.searchBar.searchTextField {
                    return field
                }
                if let field = findSearchTextField(in: viewController.view) {
                    return field
                }
                if let navigationBar = viewController.navigationController?.navigationBar,
                   let field = findSearchTextField(in: navigationBar) {
                    return field
                }
            }
            responder = responder?.next
        }
        if let window = view.window, let field = findSearchTextField(in: window) {
            return field
        }
        return nil
    }

    private func findSearchTextField(in view: UIView) -> UISearchTextField? {
        if let searchField = view as? UISearchTextField {
            return searchField
        }
        for subview in view.subviews {
            if let field = findSearchTextField(in: subview) {
                return field
            }
        }
        return nil
    }
}
#endif
