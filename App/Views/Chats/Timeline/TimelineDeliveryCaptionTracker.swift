import Foundation

/// How many captions the timeline shows: the user's delivery caption and, in
/// a group, who has seen someone else's newest message. One appearing grows
/// the timeline below the reader.
struct TimelineDeliveryCaptionTracker: Equatable {
    let target: ComposerTarget
    /// Whether any row has loaded, so the first page's arrival can be told
    /// from a caption appearing.
    let hasRows: Bool
    let captionCount: Int
}
