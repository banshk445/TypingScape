import XCTest
@testable import TypingScape

final class AdaptiveFontSizeTests: XCTestCase {
    func testUsesStandardSizeWhenRowIsWideEnough() {
        let size = AdaptiveFontSize.fontSize(forRowWidth: 100, standard: 12, minimum: 5)
        XCTAssertEqual(size, 12)
    }

    func testShrinksToFitANarrowRow() {
        let size = AdaptiveFontSize.fontSize(forRowWidth: 8, standard: 12, minimum: 5)
        XCTAssertNotNil(size)
        XCTAssertLessThan(size!, 12)
        XCTAssertGreaterThanOrEqual(size!, 5)
    }

    func testReturnsNilBelowTheMinimum() {
        XCTAssertNil(AdaptiveFontSize.fontSize(forRowWidth: 3, standard: 12, minimum: 5))
        XCTAssertNil(AdaptiveFontSize.fontSize(forRowWidth: 0, standard: 12, minimum: 5))
    }
}
