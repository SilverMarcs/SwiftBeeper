import Foundation

/// What sits above the timeline's rows: the first row and the history header.
/// A change to either moves every row below it, which `TimelineScrollAnchor`
/// undoes.
struct TimelineTopTracker: Equatable {
    let target: ComposerTarget
    let firstRowID: String?
    let isLoadingOlder: Bool
    let canLoadServerHistory: Bool
}
