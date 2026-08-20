import CoreGraphics

/// How many words a shape holds before it's visually full — the number the
/// progression gates on ("fill this shape to open the next one").
///
/// This mirrors `MountainWordCloud`'s own layout: same bottom-up rows of
/// `rowHeight`, same per-row spans from `ImageMask.horizontalExtents`, same
/// minimum gap. It has to, or the bar would sit somewhere the renderer
/// never actually reaches — the shape would read as full while the counter
/// says otherwise, or never unlock despite looking packed.
///
/// ponytail: takes one `averageWordWidth` instead of measuring each real
/// word, so a day of unusually long or short words shifts the true fill
/// point either way. Fine for a progress gate — it decides *when a shape
/// counts as done*, not what gets drawn.
enum ShapeFillEstimator {
    static func capacity(
        mask: ImageMask,
        canvas: CGSize,
        rowHeight: CGFloat,
        averageWordWidth: CGFloat,
        minGap: CGFloat
    ) -> Int {
        guard rowHeight > 0, averageWordWidth > 0, canvas.width > 0, canvas.height > 0 else { return 0 }
        let bounds = mask.contentBoundsFraction
        let contentSize = CGSize(width: bounds.width * mask.size.width, height: bounds.height * mask.size.height)
        let maskRect = AspectFit.rect(fitting: contentSize, in: canvas)
        let rowCount = max(1, Int(maskRect.height / rowHeight))

        var total = 0
        for rowFromBottom in 0..<rowCount {
            let rowY = maskRect.maxY - (CGFloat(rowFromBottom) + 0.5) * rowHeight
            guard rowY >= maskRect.minY else { break }
            let contentFy = (rowY - maskRect.minY) / maskRect.height
            let fullFy = bounds.minY + contentFy * bounds.height
            for extent in mask.horizontalExtents(atFractionY: fullFy) {
                let spanWidth = (extent.1 - extent.0) / bounds.width * maskRect.width
                guard spanWidth > 0 else { continue }
                // n words need n widths + (n-1) gaps, so solving for n adds
                // one gap to both sides rather than dividing by width alone.
                total += Int((spanWidth + minGap) / (averageWordWidth + minGap))
            }
        }
        return total
    }
}
