import CoreGraphics

/// Finds a spot for each rect via a growing spiral search around a seed
/// point, skipping anywhere outside the target region (`isInside`) or
/// overlapping an already-placed rect. This is what gives the word cloud an
/// organic, tightly-packed look instead of a rigid grid — bigger/earlier
/// words land near the seed, later ones spiral outward into whatever gaps
/// remain.
struct SpiralPlacer {
    var canvasSize: CGSize
    var isInside: (CGPoint) -> Bool
    private(set) var placedRects: [CGRect] = []

    private let angleStep: CGFloat = .pi / 12
    private let radiusStep: CGFloat
    private let maxIterations = 900
    /// Touching-but-not-overlapping rects still read as one glued-together
    /// blob of text, so require this much clearance between words too.
    private let interWordPadding: CGFloat = 3

    init(canvasSize: CGSize, isInside: @escaping (CGPoint) -> Bool) {
        self.canvasSize = canvasSize
        self.isInside = isInside
        // A fixed step size only reaches a fixed radius within the
        // iteration budget — scale it to the canvas so the spiral can
        // actually cover a 900x600 window, not just a 320x200 popover.
        let ringsAvailable = CGFloat(maxIterations) / (2 * .pi / angleStep)
        let maxRadius = (canvasSize.width * canvasSize.width + canvasSize.height * canvasSize.height).squareRoot()
        radiusStep = max(1, maxRadius / max(ringsAvailable, 1))
    }

    /// Returns nil if no spot was found within the search budget — the
    /// caller should treat that as "doesn't fit" (shape effectively full)
    /// rather than retrying forever.
    @discardableResult
    mutating func place(size: CGSize, near seed: CGPoint) -> CGRect? {
        var angle: CGFloat = 0
        var radius: CGFloat = 0
        for _ in 0..<maxIterations {
            let center = CGPoint(x: seed.x + radius * cos(angle), y: seed.y + radius * sin(angle))
            let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
            if fits(rect) {
                placedRects.append(rect)
                return rect
            }
            angle += angleStep
            if angle >= 2 * .pi {
                angle = 0
                radius += radiusStep
            }
        }
        return nil
    }

    private func fits(_ rect: CGRect) -> Bool {
        guard rect.minX >= 0, rect.minY >= 0, rect.maxX <= canvasSize.width, rect.maxY <= canvasSize.height else {
            return false
        }
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.midY),
        ]
        guard corners.allSatisfy(isInside) else { return false }
        let paddedRect = rect.insetBy(dx: -interWordPadding, dy: -interWordPadding)
        return !placedRects.contains { $0.intersects(paddedRect) }
    }
}
