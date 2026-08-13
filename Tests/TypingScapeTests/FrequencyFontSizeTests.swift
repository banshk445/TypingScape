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

    func testInterpolatesBetween() {
        let size = FrequencyFontSize.fontSize(forCount: 5, minCount: 1, maxCount: 9, minSize: 8, maxSize: 16)
        XCTAssertEqual(size, 12, accuracy: 0.01)
    }

    func testHandlesAUniformDayWithoutDividingByZero() {
        // Every word typed the same number of times — nothing to scale by.
        let size = FrequencyFontSize.fontSize(forCount: 5, minCount: 5, maxCount: 5, minSize: 8, maxSize: 16)
        XCTAssertEqual(size, 8, accuracy: 0.01)
    }
}
