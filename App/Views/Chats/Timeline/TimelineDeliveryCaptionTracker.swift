import Foundation

/// Whether the timeline ends with a delivery caption. One appearing grows the
/// timeline below the reader.
struct TimelineDeliveryCaptionTracker: Equatable {
    let target: ComposerTarget
    /// Whether any row has loaded, so the first page's arrival can be told
    /// from a caption appearing.
    let hasRows: Bool
    let showsCaption: Bool
}
