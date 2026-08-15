import XCTest
@testable import TypingScape

final class FrequencyFontSizeTests: XCTestCase {
    func testMapsLowestCountToMinSize() {
        let size = FrequencyFontSize.fontSize(forCount: 1, minCount: 1, maxCount: 10, minSize: 8, maxSize: 16)
        XCTAssertEqual(size, 8, accuracy: 0.01)
    }

    func testMapsHighestCountToMaxSize() {
        let size = FrequencyFontSize.fontSize(forCount: 10, minCount: 1, maxCount: 10, minSize: 8, maxSize: 16)
        XCTAssertEqual(size, 16, accuracy: 0.01)
    }

    func testInterpolatesOnALogCurveNotLinearly() {
        // Log-scaled: a count halfway between min and max on a LINEAR
        // scale (5, between 1 and 9) should land noticeably above the
        // linear midpoint (12) — log-scaling gives lower counts more
        // room instead of compressing them all near the minimum.
        let size = FrequencyFontSize.fontSize(forCount: 5, minCount: 1, maxCount: 9, minSize: 8, maxSize: 16)
        XCTAssertGreaterThan(size, 12)
        XCTAssertEqual(size, 8 + 8 * CGFloat(log(5.0) / log(9.0)), accuracy: 0.01)
    }

    func testCompressesHighOutliersRelativeToLinearScaling() {
        // A Zipf-skewed day: minCount=1, maxCount=20. A count of 2 (just
        // one step above the flood of count-1 words) should still land
        // meaningfully above the minimum, not get crushed near it the
        // way a linear map would (linear: (2-1)/(20-1) ≈ 0.05 -> ~8.4pt).
        let size = FrequencyFontSize.fontSize(forCount: 2, minCount: 1, maxCount: 20, minSize: 8, maxSize: 16)
        XCTAssertGreaterThan(size, 9.5)
    }

    func testHandlesAUniformDayWithoutDividingByZero() {
        // Every word typed the same number of times — nothing to scale by.
        let size = FrequencyFontSize.fontSize(forCount: 5, minCount: 5, maxCount: 5, minSize: 8, maxSize: 16)
        XCTAssertEqual(size, 8, accuracy: 0.01)
    }
}
