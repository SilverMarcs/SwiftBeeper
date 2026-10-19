import Foundation

struct RelayAction {
    let title: String
    let symbol: String
    var destructive = false
    var selected = false
    let perform: @MainActor () -> Void
}
