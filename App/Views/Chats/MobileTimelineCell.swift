#if os(iOS)
import UIKit

/// UIKit and SwiftUI share upright coordinates, including context-menu previews.
final class MobileTimelineCell: UICollectionViewCell {
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        guard let attributes = layoutAttributes.copy() as? UICollectionViewLayoutAttributes else { return layoutAttributes }
        let width = layoutAttributes.size.width
        guard width > 0 else { return attributes }

        attributes.size = fittedSize(width: width)
        return attributes
    }

    func fittedSize(width: CGFloat) -> CGSize {
        // The layout's estimated height is not a proposal for the SwiftUI row.
        // Resolve wrapping at the final width, then measure the full content.
        bounds.size.width = width
        contentView.bounds.size.width = width
        setNeedsLayout()
        layoutIfNeeded()
        let size = contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: size.height.rounded(.up))
    }
}
#endif
