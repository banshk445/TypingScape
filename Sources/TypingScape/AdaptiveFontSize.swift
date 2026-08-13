import CoreGraphics

/// Decides what font size to use for a row given how wide it actually is —
/// pure/testable so the "does this reach the tip" behavior can be verified
/// without spinning up a Canvas. Near a shape's narrow extremities (a
/// star's point, a mountain's peak) the standard size simply doesn't fit;
/// shrinking down to `minimum` lets text trace much closer to the point
/// instead of the row being skipped outright. Below `minimum`, nothing
/// legible fits and the row is left blank — a real limit of text-as-fill,
/// not a bug: a word has a minimum width, a geometric point does not.
enum AdaptiveFontSize {
    static func fontSize(forRowWidth rowWidth: CGFloat, standard: CGFloat, minimum: CGFloat) -> CGFloat? {
        guard rowWidth > 0 else { return nil }
        if rowWidth >= standard { return standard }
        guard rowWidth >= minimum else { return nil }
        return max(minimum, rowWidth * 0.85)
    }
}
