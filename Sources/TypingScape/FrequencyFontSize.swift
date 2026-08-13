import CoreGraphics

/// Maps a word's count to a font size scaled between the day's least- and
/// most-repeated word — the point being that a word typed 20 times should
/// visually pile up bigger than one typed once, not render the same size.
enum FrequencyFontSize {
    static func fontSize(forCount count: Int, minCount: Int, maxCount: Int, minSize: CGFloat, maxSize: CGFloat) -> CGFloat {
        guard maxCount > minCount else { return minSize }
        let t = CGFloat(count - minCount) / CGFloat(maxCount - minCount)
        return minSize + t * (maxSize - minSize)
    }
}
