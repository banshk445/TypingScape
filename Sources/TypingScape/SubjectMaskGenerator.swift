import CoreGraphics
import CoreImage
import CoreVideo
import ImageIO
import Vision

/// Separates the main subject of a photo/drawing from its background (the
/// same technology behind Preview's "Remove Background"), returning both a
/// plain silhouette (for placement — the row/span fill still needs a
/// simple "is this point inside" answer) and a second, richer mask whose
/// alpha follows the photo's own light and shadow within that silhouette
/// (for how densely/opaquely the fill renders). A shadowed area — an eye
/// socket, a strand of hair, a fold in clothing — reads as densely filled;
/// a bright highlight reads as barely filled at all, without needing to
/// separately detect and carve out any specific feature.
enum SubjectMaskGenerator {
    struct GeneratedMask {
        let silhouette: CGImage
        let density: CGImage
    }

    static func generate(from photo: CGImage) -> GeneratedMask? {
        // Person segmentation is a dedicated ML matte, not a color
        // heuristic — it holds up on gradient/uneven lighting (a photo's
        // skin tone fading into a dark background) where a plain color
        // test leaks. Try it first whenever the subject is a person.
        let raw = generateViaPersonSegmentation(photo)
            ?? generateViaInstanceSegmentation(photo)
            // Instance segmentation is tuned for a distinct subject (a
            // person, an object) against a background — it finds nothing
            // on a full scene or a plain line drawing. A background flood
            // fill works for both: sample the corners as the background
            // color, then anything NOT reachable from the image border
            // through that color — the subject itself, plus any
            // background-colored area it fully encloses (a line drawing's
            // blank interior, bright snow trapped inside a mountain) —
            // becomes the fill region.
            ?? generateViaBackgroundFloodFill(photo)
            ?? generateViaSaliency(photo)
        guard let raw else { return nil }
        // Instance segmentation in particular returns a soft confidence
        // map, not a hard 0/255 cut — on a low-contrast subject (pale
        // skin against a near-white background) real-but-faint parts of
        // it can genuinely score low confidence, which `ImageMask`'s
        // fixed threshold then cuts through unevenly, catching only the
        // highest-confidence sliver instead of the whole visible shape.
        // Preferring a plain darkness mask, with its rim gaps closed and
        // filled, recovers more of that faint part whenever darkness is
        // actually a meaningful signal for this photo (checked the same
        // way every other tier already does — a plausible, non-degenerate
        // fill fraction); otherwise this falls back to whatever the
        // segmentation chain above found. Real limit worth naming: a lit,
        // rounded surface (a photographed torso) is often dark only along
        // a *partial* shadow arc, not a closed rim — filling can't
        // recover an interior nothing actually encloses, so a subject
        // like that will still come through partial no matter how this
        // tier is tuned.
        let refined = darknessMask(of: photo).flatMap { candidate -> CGImage? in
            // A shadowed edge (this album cover's lit, round belly) can
            // trace only the rim of a shape, not fill it — the interior
            // faces the light and is never actually dark. Dilating the
            // mask closes small gaps in a nearly-closed rim, and filling
            // whatever that encloses recovers the interior a plain
            // per-pixel darkness test structurally can't.
            let filled = fillEnclosedRegions(of: dilated(candidate, radius: 4) ?? candidate) ?? candidate
            // Plain darkness has no notion of "one subject" — a stray
            // dark spot anywhere else in the photo (a printed word, a
            // shadow, a logo) becomes its own disconnected island in the
            // mask, scattered text the fill algorithm has no reason to
            // treat as part of the same shape. Keeping only the single
            // largest connected region discards those as noise.
            let isolated = significantConnectedComponents(of: filled) ?? filled
            // A shadow arc that only traces part of a rounded subject's
            // rim (this album cover's belly, lit on its far side) has no
            // enclosed interior for `fillEnclosedRegions` to find at any
            // dilation radius — the far side simply has no dark pixels to
            // connect. Filling each component to its own convex hull
            // recovers that interior directly from the rim's own shape.
            let hulled = hullFilledForThinComponents(of: isolated) ?? isolated
            let fraction = fillFraction(of: hulled)
            return (fraction > 0.03 && fraction < 0.85) ? hulled : nil
        } ?? raw
        guard let silhouette = smoothedEdges(refined) else { return nil }
        let density = luminanceWeighted(bySilhouette: silhouette, photo: photo) ?? silhouette
        return GeneratedMask(silhouette: silhouette, density: density)
    }

    /// Reweights `silhouette`'s alpha by the original photo's own
    /// luminance: darker pixels (in shadow, or just a darker tone/color)
    /// get a higher alpha, lighter pixels a lower one, all scaled by the
    /// silhouette's own alpha so the result stays 0 outside it and keeps
    /// the same soft outer edge.
    private static func luminanceWeighted(bySilhouette silhouette: CGImage, photo: CGImage) -> CGImage? {
        let width = silhouette.width, height = silhouette.height
        guard width > 0, height > 0 else { return nil }

        var silhouetteData = [UInt8](repeating: 0, count: width * height * 4)
        guard let silhouetteContext = CGContext(
            data: &silhouetteData, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        silhouetteContext.draw(silhouette, in: CGRect(x: 0, y: 0, width: width, height: height))

        var photoData = [UInt8](repeating: 0, count: width * height * 4)
        guard let photoContext = CGContext(
            data: &photoData, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        photoContext.draw(photo, in: CGRect(x: 0, y: 0, width: width, height: height))

        var result = [UInt8](repeating: 0, count: width * height * 4)
        for p in 0..<(width * height) {
            let i = p * 4
            let silhouetteAlpha = Double(silhouetteData[i + 3]) / 255
            guard silhouetteAlpha > 0 else { continue }
            let luminance = (0.299 * Double(photoData[i]) + 0.587 * Double(photoData[i + 1]) + 0.114 * Double(photoData[i + 2])) / 255
            // A raw linear (1 - luminance) leaves a lot of the fill too
            // faint to read (most photos skew bright/midtone) and lets
            // the very brightest spots fade to nearly invisible. `pow`
            // pulls midtones up so more of the fill reads clearly, and a
            // floor keeps even a bright highlight legibly dim rather than
            // vanishing — the tonal contrast comes through as "clearer
            // vs. dimmer text", not "text vs. blank paper".
            let minDensity = 0.32
            let density = minDensity + (1 - minDensity) * pow(1 - luminance, 0.6)
            result[i + 3] = UInt8(max(0, min(255, density * 255 * silhouetteAlpha)))
        }
        guard let outContext = CGContext(
            data: &result, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return outContext.makeImage()
    }

    /// A pixel counts as "subject" simply if it's dark. Tried layering
    /// this on top of the ML segmentation (as a confidence-seeded,
    /// reachability-gated grow) first, but the model gave essentially
    /// zero confidence over this subject's real-but-unlit part (a belly
    /// next to a confidently-detected glove) — and there's a genuinely
    /// not-dark gap between the two in the photo itself, so nothing
    /// reachability-based ever bridged it. Plain darkness, with no ML
    /// involved at all, is what actually matched a person looking at the
    /// photo and calling this "the shape". Note this only ever traces
    /// dark pixels — a lit, rounded surface (this photo's belly) is dark
    /// only along its shadowed rim, not through its whole interior;
    /// `fillEnclosedRegions` is what turns that rim into a filled shape.
    private static func darknessMask(of photo: CGImage, darknessThreshold: Double = 210) -> CGImage? {
        let width = photo.width, height = photo.height
        guard width > 0, height > 0 else { return nil }

        var photoData = [UInt8](repeating: 0, count: width * height * 4)
        guard let photoContext = CGContext(
            data: &photoData, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        photoContext.draw(photo, in: CGRect(x: 0, y: 0, width: width, height: height))

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for p in 0..<(width * height) {
            let i = p * 4
            let luminance = 0.299 * Double(photoData[i]) + 0.587 * Double(photoData[i + 1]) + 0.114 * Double(photoData[i + 2])
            rgba[i + 3] = luminance < darknessThreshold ? 255 : 0
        }
        guard let outContext = CGContext(
            data: &rgba, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return outContext.makeImage()
    }

    /// Grows the mask outward by `radius` in every direction (a
    /// separable box dilation — two 1D passes instead of a full 2D
    /// kernel, so this stays fast at real photo resolutions). Closes
    /// small gaps in a rim that's *almost* a closed loop, which is what
    /// lets `fillEnclosedRegions` treat it as one afterward.
    private static func dilated(_ mask: CGImage, radius: Int) -> CGImage? {
        let width = mask.width, height = mask.height
        guard width > 0, height > 0, radius > 0 else { return mask }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))

        let inside = (0..<(width * height)).map { data[$0 * 4 + 3] > 128 }

        var horizontal = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                let lo = max(0, x - radius), hi = min(width - 1, x + radius)
                horizontal[row + x] = (lo...hi).contains { inside[row + $0] }
            }
        }
        var result = [Bool](repeating: false, count: width * height)
        for x in 0..<width {
            for y in 0..<height {
                let lo = max(0, y - radius), hi = min(height - 1, y + radius)
                result[y * width + x] = (lo...hi).contains { horizontal[$0 * width + x] }
            }
        }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for p in 0..<(width * height) where result[p] { rgba[p * 4 + 3] = 255 }
        guard let outContext = CGContext(
            data: &rgba, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return outContext.makeImage()
    }

    /// Flood-fills from the image border through everything NOT already
    /// in the mask; whatever that flood never reaches is enclosed by the
    /// mask's own boundary and gets added — the same "fill the region an
    /// outline encloses" idea `generateViaBackgroundFloodFill` uses on a
    /// photo's raw colors, applied here to an already-computed mask so a
    /// closed (or nearly-closed, after `dilated`) rim becomes a filled
    /// shape instead of staying a hollow ring.
    private static func fillEnclosedRegions(of mask: CGImage) -> CGImage? {
        let width = mask.width, height = mask.height
        guard width > 0, height > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))

        let isInside = (0..<(width * height)).map { data[$0 * 4 + 3] > 128 }
        var reachedOutside = [Bool](repeating: false, count: width * height)
        var queue: [Int] = []
        func tryEnqueue(_ x: Int, _ y: Int) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let p = y * width + x
            guard !isInside[p], !reachedOutside[p] else { return }
            reachedOutside[p] = true
            queue.append(p)
        }
        for x in 0..<width { tryEnqueue(x, 0); tryEnqueue(x, height - 1) }
        for y in 0..<height { tryEnqueue(0, y); tryEnqueue(width - 1, y) }
        var head = 0
        while head < queue.count {
            let p = queue[head]; head += 1
            let x = p % width, y = p / width
            tryEnqueue(x - 1, y); tryEnqueue(x + 1, y)
            tryEnqueue(x, y - 1); tryEnqueue(x, y + 1)
        }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for p in 0..<(width * height) where isInside[p] || !reachedOutside[p] { rgba[p * 4 + 3] = 255 }
        guard let outContext = CGContext(
            data: &rgba, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return outContext.makeImage()
    }

    /// Keeps every 4-connected region of "inside" pixels big enough to
    /// plausibly be a real part of the subject, discarding tiny ones — a
    /// plain darkness test has no notion of "the subject" as one thing,
    /// so a stray dark spot elsewhere in the photo (printed text, a
    /// small shadow, a logo) becomes its own disconnected island with no
    /// relation to the real subject. Sized relative to the *largest*
    /// component rather than an absolute pixel count, since a real
    /// subject can legitimately be split across several substantial but
    /// disconnected pieces (a hand and a shadowed torso with a bright
    /// gap between them) — keeping only the single biggest one would
    /// throw the rest away just as wrongly as keeping every fleck of noise.
    private static func significantConnectedComponents(of mask: CGImage, relativeSizeThreshold: Double = 0.15) -> CGImage? {
        let width = mask.width, height = mask.height
        guard width > 0, height > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))

        let isInside = (0..<(width * height)).map { data[$0 * 4 + 3] > 128 }
        let components = connectedComponents(isInside: isInside, width: width, height: height)
        guard let largest = components.map(\.count).max() else { return nil }
        let minSize = Double(largest) * relativeSizeThreshold

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for component in components where Double(component.count) >= minSize {
            for p in component { rgba[p * 4 + 3] = 255 }
        }
        guard let outContext = CGContext(
            data: &rgba, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return outContext.makeImage()
    }

    /// 4-connected BFS labeling shared by every pass that needs to reason
    /// about the mask one physically-connected piece at a time.
    private static func connectedComponents(isInside: [Bool], width: Int, height: Int) -> [[Int]] {
        var visited = [Bool](repeating: false, count: width * height)
        var components: [[Int]] = []
        var queue: [Int] = []
        for start in 0..<(width * height) where isInside[start] && !visited[start] {
            queue.removeAll(keepingCapacity: true)
            queue.append(start)
            visited[start] = true
            var component = [start]
            var head = 0
            while head < queue.count {
                let p = queue[head]; head += 1
                let x = p % width, y = p / width
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let np = ny * width + nx
                    guard isInside[np], !visited[np] else { continue }
                    visited[np] = true
                    queue.append(np)
                    component.append(np)
                }
            }
            components.append(component)
        }
        return components
    }

    /// A rim that broke under `significantConnectedComponents` doesn't
    /// break into one thin, low-solidity piece — each surviving fragment
    /// can look perfectly solid on its own (a fairly straight arc
    /// segment isn't very concave by itself). The missing interior lives
    /// in the *gap between* fragments, not inside any single one of
    /// them, so hulling them individually never finds it. Instead, treat
    /// the single largest component as the anchor subject (a hand,
    /// fingers and all) and always keep it exactly as detected, then
    /// pool every other surviving fragment into one point cloud — if
    /// *that* combined shape is a small fraction of its own hull's area,
    /// the fragments are pieces of one interrupted rim (this album
    /// cover's belly) and get filled solid together; otherwise each is
    /// left untouched, in case they're independently meaningful.
    private static func hullFilledForThinComponents(of mask: CGImage, solidityThreshold: Double = 0.4) -> CGImage? {
        let width = mask.width, height = mask.height
        guard width > 0, height > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))

        let isInside = (0..<(width * height)).map { data[$0 * 4 + 3] > 128 }
        let components = connectedComponents(isInside: isInside, width: width, height: height)
            .sorted { $0.count > $1.count }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        if let anchor = components.first {
            for p in anchor { rgba[p * 4 + 3] = 255 }
        }
        let fragments = components.dropFirst()
        if !fragments.isEmpty {
            let pooled = fragments.flatMap { $0 }
            let points = pooled.map { CGPoint(x: $0 % width, y: $0 / width) }
            let hull = convexHull(of: points)
            let hullArea = polygonArea(hull)
            let solidity = hullArea > 0 ? Double(pooled.count) / hullArea : 1
            if solidity < solidityThreshold, hull.count >= 3 {
                fillPolygon(hull, width: width, height: height) { rgba[$0 * 4 + 3] = 255 }
            } else {
                for p in pooled { rgba[p * 4 + 3] = 255 }
            }
        }
        guard let outContext = CGContext(
            data: &rgba, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return outContext.makeImage()
    }

    /// Andrew's monotone chain, on integer pixel coordinates.
    private static func convexHull(of points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard sorted.count >= 3 else { return sorted }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [CGPoint] = []
        for p in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }
        var upper: [CGPoint] = []
        for p in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    private static func polygonArea(_ polygon: [CGPoint]) -> Double {
        guard polygon.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(Double(sum)) / 2
    }

    private static func fillPolygon(_ polygon: [CGPoint], width: Int, height: Int, set: (Int) -> Void) {
        guard polygon.count >= 3, let minY = polygon.map(\.y).min(), let maxY = polygon.map(\.y).max() else { return }
        let yLo = max(0, Int(minY.rounded(.down)))
        let yHi = min(height - 1, Int(maxY.rounded(.up)))
        guard yLo <= yHi else { return }
        for y in yLo...yHi {
            let yc = CGFloat(y) + 0.5
            var xs: [CGFloat] = []
            for i in 0..<polygon.count {
                let a = polygon[i], b = polygon[(i + 1) % polygon.count]
                if (a.y <= yc && b.y > yc) || (b.y <= yc && a.y > yc) {
                    xs.append(a.x + (yc - a.y) / (b.y - a.y) * (b.x - a.x))
                }
            }
            xs.sort()
            var i = 0
            while i + 1 < xs.count {
                let xStart = max(0, Int(xs[i].rounded()))
                let xEnd = min(width - 1, Int(xs[i + 1].rounded()) - 1)
                if xStart <= xEnd { for x in xStart...xEnd { set(y * width + x) } }
                i += 2
            }
        }
    }

    private static func generateViaPersonSegmentation(_ photo: CGImage) -> CGImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: photo, options: [:])
        guard (try? handler.perform([request])) != nil,
              let result = request.results?.first,
              let mask = alphaImage(fromGrayscaleMask: result.pixelBuffer)
        else { return nil }
        // Unlike instance segmentation, this request always "succeeds" even
        // with no person in frame — it just returns a near-empty mask. Only
        // trust it if it actually covers a plausible chunk of the photo.
        let fraction = fillFraction(of: mask)
        guard fraction > 0.05, fraction < 0.95 else { return nil }
        return mask
    }

    private static func fillFraction(of cgImage: CGImage, threshold: UInt8 = 32) -> Double {
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0 else { return 0 }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var covered = 0
        for p in 0..<(width * height) where data[p * 4 + 3] > threshold { covered += 1 }
        return Double(covered) / Double(width * height)
    }

    private static let ciContext = CIContext()

    private static func smoothedEdges(_ mask: CGImage, radius: Double = 1.0) -> CGImage? {
        let ciImage = CIImage(cgImage: mask)
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return mask }
        blur.setValue(ciImage, forKey: kCIInputImageKey)
        blur.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = blur.outputImage,
              let cgImage = ciContext.createCGImage(output, from: ciImage.extent)
        else { return mask }
        return cgImage
    }

    private static func generateViaBackgroundFloodFill(_ photo: CGImage) -> CGImage? {
        let width = photo.width, height = photo.height
        guard width > 0, height > 0 else { return nil }

        var src = [UInt8](repeating: 0, count: width * height * 4)
        guard let readContext = CGContext(
            data: &src, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        readContext.draw(photo, in: CGRect(x: 0, y: 0, width: width, height: height))

        func rgb(_ p: Int) -> (Int, Int, Int) {
            let i = p * 4
            return (Int(src[i]), Int(src[i + 1]), Int(src[i + 2]))
        }

        let corners = [0, width - 1, (height - 1) * width, (height - 1) * width + width - 1].map(rgb)
        let refR = corners.map(\.0).reduce(0, +) / corners.count
        let refG = corners.map(\.1).reduce(0, +) / corners.count
        let refB = corners.map(\.2).reduce(0, +) / corners.count
        let tolerance = 40

        var isBackgroundColor = [Bool](repeating: false, count: width * height)
        for p in 0..<(width * height) {
            let (r, g, b) = rgb(p)
            isBackgroundColor[p] = abs(r - refR) < tolerance && abs(g - refG) < tolerance && abs(b - refB) < tolerance
        }

        // Flood-fill from the border through background-colored pixels
        // only, so anything the color test would call "background" but
        // isn't actually connected to the real exterior background stays
        // part of the fill region instead of punching a hole in it.
        var reachedBackground = [Bool](repeating: false, count: width * height)
        var queue: [Int] = []
        queue.reserveCapacity(width * height / 4)
        func tryEnqueue(_ x: Int, _ y: Int) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let p = y * width + x
            guard isBackgroundColor[p], !reachedBackground[p] else { return }
            reachedBackground[p] = true
            queue.append(p)
        }
        for x in 0..<width { tryEnqueue(x, 0); tryEnqueue(x, height - 1) }
        for y in 0..<height { tryEnqueue(0, y); tryEnqueue(width - 1, y) }

        var head = 0
        while head < queue.count {
            let p = queue[head]; head += 1
            let x = p % width, y = p / width
            tryEnqueue(x - 1, y); tryEnqueue(x + 1, y); tryEnqueue(x, y - 1); tryEnqueue(x, y + 1)
        }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        var fillCount = 0
        for p in 0..<(width * height) where !reachedBackground[p] {
            rgba[p * 4 + 3] = 255
            fillCount += 1
        }
        let fraction = Double(fillCount) / Double(width * height)
        guard fraction > 0.05, fraction < 0.95 else { return nil }

        guard let writeContext = CGContext(
            data: &rgba, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return writeContext.makeImage()
    }

    private static func generateViaInstanceSegmentation(_ photo: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: photo, options: [:])
        guard (try? handler.perform([request])) != nil,
              let result = request.results?.first,
              !result.allInstances.isEmpty,
              let maskBuffer = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler),
              let mask = alphaImage(fromGrayscaleMask: maskBuffer)
        else { return nil }
        // A busy photo can register a spuriously tiny "instance" (a stray
        // object at the frame's edge) that would otherwise win outright and
        // skip the fallbacks that might actually find the real subject —
        // same sanity check `generateViaPersonSegmentation` already needed.
        let fraction = fillFraction(of: mask)
        guard fraction > 0.05, fraction < 0.95 else { return nil }
        return mask
    }

    private static func generateViaSaliency(_ photo: CGImage) -> CGImage? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: photo, options: [:])
        guard (try? handler.perform([request])) != nil,
              let result = request.results?.first
        else { return nil }
        // Saliency scores for a scenic photo can peak well under 1.0 (e.g.
        // ~0.2), so a fixed absolute cutoff misses everything — threshold
        // relative to this image's own observed range instead.
        return alphaImage(fromGrayscaleMask: result.pixelBuffer, relativeThreshold: 0.35)
    }

    /// Instance masks come back 8-bit grayscale; saliency maps come back
    /// single-channel float32 (0...1) — either way, `ImageMask` samples
    /// alpha, so this repacks the grayscale/float value as the alpha
    /// channel of an otherwise-black RGBA image. `relativeThreshold`, if
    /// given, binarizes at that fraction of this buffer's own min...max
    /// range instead of keeping the raw gradient.
    private static func alphaImage(fromGrayscaleMask pixelBuffer: CVPixelBuffer, relativeThreshold: Float? = nil) -> CGImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let isFloat = CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_OneComponent32Float
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        func rawValue(_ x: Int, _ row: UnsafeMutableRawPointer) -> Float {
            isFloat
                ? row.assumingMemoryBound(to: Float32.self)[x]
                : Float(row.assumingMemoryBound(to: UInt8.self)[x]) / 255
        }

        var minV: Float = .greatestFiniteMagnitude, maxV: Float = 0
        if relativeThreshold != nil {
            for y in 0..<height {
                let row = base.advanced(by: y * bytesPerRow)
                for x in 0..<width {
                    let v = rawValue(x, row)
                    minV = min(minV, v); maxV = max(maxV, v)
                }
            }
        }
        let cutoff = minV + (maxV - minV) * (relativeThreshold ?? 0)

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let row = base.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let v = rawValue(x, row)
                let alpha: UInt8 = relativeThreshold != nil
                    ? (v > cutoff ? 255 : 0)
                    : UInt8(max(0, min(1, v)) * 255)
                rgba[(y * width + x) * 4 + 3] = alpha
            }
        }
        guard let context = CGContext(
            data: &rgba, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return context.makeImage()
    }
}
