import XCTest
@testable import TypingScape

final class AspectFitTests: XCTestCase {
    func testLetterboxesAWiderBoundsThanContent() {
        // Square content (1:1) in a much wider box (2:1) -> pillarboxed,
        // height matches bounds, width shrinks to keep the square aspect.
        let rect = AspectFit.rect(fitting: CGSize(width: 100, height: 100), in: CGSize(width: 200, height: 100))
        XCTAssertEqual(rect.height, 100, accuracy: 0.01)
        XCTAssertEqual(rect.width, 100, accuracy: 0.01)
        XCTAssertEqual(rect.minX, 50, accuracy: 0.01)
    }

    func testLetterboxesATallerBoundsThanContent() {
        let rect = AspectFit.rect(fitting: CGSize(width: 100, height: 100), in: CGSize(width: 100, height: 200))
        XCTAssertEqual(rect.width, 100, accuracy: 0.01)
        XCTAssertEqual(rect.height, 100, accuracy: 0.01)
        XCTAssertEqual(rect.minY, 50, accuracy: 0.01)
    }

    func testMatchingAspectFillsBoundsExactly() {
        let rect = AspectFit.rect(fitting: CGSize(width: 4, height: 3), in: CGSize(width: 800, height: 600))
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 800, height: 600))
    }
}
