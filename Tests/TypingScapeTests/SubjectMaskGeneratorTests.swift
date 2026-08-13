import XCTest
@testable import TypingScape

final class SubjectMaskGeneratorTests: XCTestCase {
    func testGeneratesAMaskForTheBundledImage() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "mountain-outline", withExtension: "png"))
        let provider = try XCTUnwrap(CGDataProvider(url: url as CFURL))
        let photo = try XCTUnwrap(CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))

        let subject = try XCTUnwrap(SubjectMaskGenerator.generate(from: photo))
        let mask = try XCTUnwrap(ImageMask(cgImage: subject))

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
}
