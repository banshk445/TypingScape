import CoreGraphics

/// Maps a word's count to a font size scaled between the day's least- and
/// most-repeated word — the point being that a word typed 20 times should
/// visually pile up bigger than one typed once, not render the same size.
enum FrequencyFontSize {
    static func fontSize(forCount count: Int, minCount: Int, maxCount: Int, minSize: CGFloat, maxSize: CGFloat) -> CGFloat {
        guard maxCount > minCount else { return minSize }
        // Real typed-word counts skew hard (Zipf's law: a handful of
        // words dominate the day, most show up once or twice). Scaling
        // linearly crushes that ~90% into the same minimum size and
        // blows the rare outliers up to the max, repeated across the
        // whole shape wherever they land in the cycle — log-scaling
        // compresses the outliers and actually spreads the bulk of
        // ordinary words across a usable size range instead.
        let logMin = log(Double(max(1, minCount)))
        let logMax = log(Double(max(1, maxCount)))
        guard logMax > logMin else { return minSize }
        let t = (log(Double(max(1, count))) - logMin) / (logMax - logMin)
        return minSize + CGFloat(max(0, min(1, t))) * (maxSize - minSize)
    }
}
