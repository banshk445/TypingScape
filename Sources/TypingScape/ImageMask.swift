import CoreGraphics
import SwiftUI

/// Samples a rendered image's alpha channel to decide whether a point is
/// "inside" the region words are allowed to fill. This is the seam that
/// lets the fill region come from any image — a vector shape rendered to a
/// bitmap today, a real photo or preset picture later — without touching
/// the placement code at all.
struct ImageMask {
    /// Anti-aliased edges from `ImageRenderer`/photo segmentation leave a
    /// fringe of partially-transparent pixels around every boundary. A low
    /// threshold (e.g. >32/255) counts that faint fringe as "inside", which
    /// matters most where the shape is already thin (a mountain's peak) —
    /// requiring at least half-opacity keeps the boundary to the visually
    /// solid part of the shape.
    private static let insideThreshold: UInt8 = 128

    private let pixelData: [UInt8]
    private let width: Int
    private let height: Int
    /// Center of mass of the fill region, in the same 0...1 fractional
    /// space as `isInside(atFraction:)` — a good default seed point for
    /// placement, since it works for any mask shape without assuming
    /// where the "middle" of the interesting area actually is.
    let centroidFraction: CGPoint
    /// Center of the fill region's lowest (largest-y) row — lets placement
    /// start from the bottom and grow upward, like the mountain filling up,
    /// instead of spreading out equally from the center in every direction.
    let bottomFraction: CGPoint
    /// The source bitmap, kept around so the boundary itself can be drawn
    /// (not just used to test points) — that's what makes the fill region
    /// read as an actual bounded shape instead of a loose cloud of words.
    let cgImage: CGImage
    var size: CGSize { CGSize(width: width, height: height) }
    /// Tight bounding box of the fill region, in fractional (0...1) terms.
    /// A source image often has blank margin around the actual drawing —
    /// fitting to the full image size shrinks the shape to accommodate
    /// that margin; fitting to this instead lets the real shape fill the
    /// available space edge to edge.
    let contentBoundsFraction: CGRect

    init?(cgImage: CGImage) {
        self.cgImage = cgImage
        width = cgImage.width
        height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        pixelData = data

        var sumX = 0.0, sumY = 0.0, count = 0.0
        var maxY = -1
        var maxYSumX = 0.0, maxYCount = 0.0
        var minInsideX = width, maxInsideX = -1, minInsideY = height, maxInsideY = -1
        for y in 0..<height {
            for x in 0..<width where data[(y * width + x) * 4 + 3] > Self.insideThreshold {
                sumX += Double(x); sumY += Double(y); count += 1
                if y > maxY {
                    maxY = y
                    maxYSumX = 0
                    maxYCount = 0
                }
                maxYSumX += Double(x)
                maxYCount += 1
                minInsideX = min(minInsideX, x); maxInsideX = max(maxInsideX, x)
                minInsideY = min(minInsideY, y); maxInsideY = max(maxInsideY, y)
            }
        }
        centroidFraction = count > 0
            ? CGPoint(x: sumX / count / Double(width), y: sumY / count / Double(height))
            : CGPoint(x: 0.5, y: 0.5)
        bottomFraction = maxY >= 0
            ? CGPoint(x: maxYSumX / maxYCount / Double(width), y: Double(maxY) / Double(height))
            : CGPoint(x: 0.5, y: 0.9)
        contentBoundsFraction = maxInsideX >= 0
            ? CGRect(
                x: Double(minInsideX) / Double(width), y: Double(minInsideY) / Double(height),
                width: Double(maxInsideX - minInsideX + 1) / Double(width),
                height: Double(maxInsideY - minInsideY + 1) / Double(height)
            )
            : CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    /// The source bitmap cropped to `contentBoundsFraction` — draw this
    /// instead of `cgImage` to show the shape without its blank margin.
    func croppedToContent() -> CGImage? {
        let rect = CGRect(
            x: contentBoundsFraction.minX * CGFloat(width), y: contentBoundsFraction.minY * CGFloat(height),
            width: contentBoundsFraction.width * CGFloat(width), height: contentBoundsFraction.height * CGFloat(height)
        )
        return cgImage.cropping(to: rect)
    }

    /// Same crop as `croppedToContent()`, but recolored to a flat tint —
    /// the source photo's own colors would fight a custom app background,
    /// so this repaints the silhouette in whatever color fits the theme.
    func tintedCroppedContent(red: UInt8, green: UInt8, blue: UInt8) -> CGImage? {
        let originX = Int(contentBoundsFraction.minX * CGFloat(width))
        let originY = Int(contentBoundsFraction.minY * CGFloat(height))
        let cropW = Int(contentBoundsFraction.width * CGFloat(width))
        let cropH = Int(contentBoundsFraction.height * CGFloat(height))
        guard cropW > 0, cropH > 0 else { return nil }

        var rgba = [UInt8](repeating: 0, count: cropW * cropH * 4)
        for y in 0..<cropH {
            for x in 0..<cropW {
                let srcIndex = ((originY + y) * width + (originX + x)) * 4
                let dstIndex = (y * cropW + x) * 4
                rgba[dstIndex] = red; rgba[dstIndex + 1] = green; rgba[dstIndex + 2] = blue
                rgba[dstIndex + 3] = pixelData[srcIndex + 3]
            }
        }
        guard let context = CGContext(
            data: &rgba, width: cropW, height: cropH, bitsPerComponent: 8,
            bytesPerRow: cropW * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return context.makeImage()
    }

    /// Renders arbitrary SwiftUI content (a Shape, an Image, anything) to a
    /// bitmap and wraps it as a mask — the fill-in for "load a real photo"
    /// until that's wired up.
    @MainActor
    static func render(_ content: some View, size: CGSize) -> ImageMask? {
        let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { return nil }
        return ImageMask(cgImage: cgImage)
    }

    /// `point` is in the mask's own pixel space.
    func isInside(_ point: CGPoint) -> Bool {
        let x = Int(point.x)
        let y = Int(point.y)
        guard x >= 0, x < width, y >= 0, y < height else { return false }
        let alphaIndex = (y * width + x) * 4 + 3
        return pixelData[alphaIndex] > Self.insideThreshold
    }

    /// `point` is fractional (0...1 on each axis), independent of the
    /// mask's actual pixel resolution vs. whatever it's being drawn at.
    func isInside(atFraction point: CGPoint) -> Bool {
        isInside(CGPoint(x: point.x * CGFloat(width), y: point.y * CGFloat(height)))
    }

    /// The bounds of *every contiguous run* of fill-region pixels at a
    /// given fractional row, as fractional x ranges, left to right. A
    /// naive leftmost-to-rightmost span is wrong for non-convex shapes —
    /// it either bridges a gap the shape doesn't have (a star's bottom
    /// notch) or, if collapsed to just the longest run, silently drops
    /// every other span on that row (a sea's separate wave crests). Each
    /// run is real fill region and needs to be filled on its own.
    func horizontalExtents(atFractionY fy: CGFloat) -> [(CGFloat, CGFloat)] {
        guard fy >= 0, fy <= 1 else { return [] }
        let y = min(height - 1, max(0, Int(fy * CGFloat(height))))

        var runs: [(CGFloat, CGFloat)] = []
        var runStart: Int?
        func closeRun(endingBefore x: Int) {
            guard let start = runStart else { return }
            runs.append((CGFloat(start) / CGFloat(width), CGFloat(x) / CGFloat(width)))
            runStart = nil
        }
        for x in 0..<width {
            let isInside = pixelData[(y * width + x) * 4 + 3] > Self.insideThreshold
            if isInside {
                if runStart == nil { runStart = x }
            } else {
                closeRun(endingBefore: x)
            }
        }
        closeRun(endingBefore: width)
        return runs
    }
}
