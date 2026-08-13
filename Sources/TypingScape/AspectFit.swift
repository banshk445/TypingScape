import CoreGraphics

enum AspectFit {
    /// Largest rect of `contentSize`'s aspect ratio that fits centered
    /// within `bounds` — letterboxing a non-matching aspect ratio instead
    /// of stretching it.
    static func rect(fitting contentSize: CGSize, in bounds: CGSize) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let contentAspect = contentSize.width / contentSize.height
        let boundsAspect = bounds.width / bounds.height
        var fitted = bounds
        if contentAspect > boundsAspect {
            fitted.height = bounds.width / contentAspect
        } else {
            fitted.width = bounds.height * contentAspect
        }
        let origin = CGPoint(x: (bounds.width - fitted.width) / 2, y: (bounds.height - fitted.height) / 2)
        return CGRect(origin: origin, size: fitted)
    }
}
