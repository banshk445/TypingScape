import XCTest
@testable import TypingScape

final class SubjectMaskGeneratorTests: XCTestCase {
    func testGeneratesAMaskForTheBundledImage() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "mountain-outline", withExtension: "png"))
        let provider = try XCTUnwrap(CGDataProvider(url: url as CFURL))
        let photo = try XCTUnwrap(CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))

        let generated = try XCTUnwrap(SubjectMaskGenerator.generate(from: photo))
        let mask = try XCTUnwrap(ImageMask(cgImage: generated.silhouette, densityImage: generated.density))

        // The mask should select a real region, not everything (mask
        // generation silently failing open) or nothing (threshold too
        // strict).
        var insideCount = 0
        let samples = 20
        for yi in 0..<samples {
            for xi in 0..<samples {
                let fx = CGFloat(xi) / CGFloat(samples - 1)
                let fy = CGFloat(yi) / CGFloat(samples - 1)
                if mask.isInside(atFraction: CGPoint(x: fx, y: fy)) { insideCount += 1 }
            }
        }
        let fraction = Double(insideCount) / Double(samples * samples)
        XCTAssertGreaterThan(fraction, 0.05)
        XCTAssertLessThan(fraction, 0.95)
    }

    func testDensityMaskVariesWithThePhotosOwnTone() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "mountain-outline", withExtension: "png"))
        let provider = try XCTUnwrap(CGDataProvider(url: url as CFURL))
        let photo = try XCTUnwrap(CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        let generated = try XCTUnwrap(SubjectMaskGenerator.generate(from: photo))

        let density = generated.density
        let width = density.width, height = density.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(density, in: CGRect(x: 0, y: 0, width: width, height: height))

        var alphaValues = Set<UInt8>()
        for p in 0..<(width * height) { alphaValues.insert(data[p * 4 + 3]) }
        // A flat silhouette would only ever produce ~2 alpha values (0 and
        // 255, plus a thin AA fringe); real tonal variation produces many
        // distinct intermediate values across the inside region.
        XCTAssertGreaterThan(alphaValues.count, 10)
    }

    func testLowContrastSubjectAgainstANearWhiteBackgroundIsMostlyCaptured() throws {
        // album-cover.png is a pale/low-contrast subject (skin tone, a
        // black glove) against a near-white background — instance
        // segmentation's confidence for the low-contrast parts of the
        // subject used to land under the fixed inside-threshold, cutting
        // the mask down to just the glove (~0.18 fill fraction). The
        // gamma boost in `generate` should recover most of the subject.
        let url = try XCTUnwrap(Bundle.module.url(forResource: "album-cover", withExtension: "png"))
        let provider = try XCTUnwrap(CGDataProvider(url: url as CFURL))
        let photo = try XCTUnwrap(CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))

        let generated = try XCTUnwrap(SubjectMaskGenerator.generate(from: photo))
        let mask = try XCTUnwrap(ImageMask(cgImage: generated.silhouette, densityImage: generated.density))

        var insideCount = 0
        let samples = 30
        for yi in 0..<samples {
            for xi in 0..<samples {
                let fx = CGFloat(xi) / CGFloat(samples - 1)
                let fy = CGFloat(yi) / CGFloat(samples - 1)
                if mask.isInside(atFraction: CGPoint(x: fx, y: fy)) { insideCount += 1 }
            }
        }
        let fraction = Double(insideCount) / Double(samples * samples)
        XCTAssertGreaterThan(fraction, 0.25)
    }
}
