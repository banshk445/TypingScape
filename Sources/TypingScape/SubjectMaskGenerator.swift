import CoreGraphics
import CoreImage
import CoreVideo
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
        // Instance segmentation in particular returns a soft confidence
        // map, not a hard 0/255 cut — on a low-contrast subject (pale
        // skin against a near-white background) real-but-faint parts of
        // it can genuinely score low confidence, which `ImageMask`'s
        // fixed threshold then cuts through unevenly, catching only the
        // highest-confidence sliver instead of the whole visible shape.
        // Gamma-boosting each mask's own alpha is a no-op for anything
        // already-binary (person seg, flood fill, saliency's own
        // threshold) and fixes exactly this case.
        guard let raw, let boosted = gammaBoosted(raw), let silhouette = smoothedEdges(boosted) else { return nil }
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
            result[i + 3] = UInt8(max(0, min(255, (1 - luminance) * 255 * silhouetteAlpha)))
        }
        guard let outContext = CGContext(
            data: &result, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return outContext.makeImage()
    }

    /// Boosts this mask's own alpha with `alpha' = (alpha/255)^gamma *
    /// 255` (gamma < 1). A hard-edged mask (person segmentation, flood
    /// fill, saliency's own threshold) only has values at/near 0 and 255,
    /// which this leaves essentially unchanged; it's a soft confidence
    /// map (instance segmentation) that this actually reshapes — a
    /// low-contrast subject (pale skin against a near-white background)
    /// can genuinely score low-but-real confidence (not just a narrow
    /// band — contrast-stretching a range that already spans 0...255
    /// does nothing here) that a linear/fixed threshold cuts through
    /// unevenly. Pulling mid-low values up nonlinearly, without moving
    /// values already near 0 or 255, lets a real-but-faint part of the
    /// subject cross the threshold without dragging the background with it.
    private static func gammaBoosted(_ mask: CGImage, gamma: Double = 0.5) -> CGImage? {
        let width = mask.width, height = mask.height
        guard width > 0, height > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))

        for p in 0..<(width * height) {
            let i = p * 4 + 3
            let normalized = Double(data[i]) / 255
            data[i] = UInt8(min(255, max(0, pow(normalized, gamma) * 255)))
        }
        return context.makeImage()
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

    private static func smoothedEdges(_ mask: CGImage, radius: Double = 2.2) -> CGImage? {
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
