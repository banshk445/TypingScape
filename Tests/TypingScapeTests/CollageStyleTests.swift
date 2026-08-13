import XCTest
@testable import TypingScape

final class CollageStyleTests: XCTestCase {
    func testSameIndexAlwaysProducesTheSameStyle() {
        let a = CollageStyle.style(forWord: "산책", index: 7, fontSize: 12)
        let b = CollageStyle.style(forWord: "산책", index: 7, fontSize: 12)
        XCTAssertEqual(a.rotationDegrees, b.rotationDegrees)
        XCTAssertEqual(a.displayWord, b.displayWord)
    }

    func testDifferentIndicesProduceSomeVariety() {
        let styles = (0..<20).map { CollageStyle.style(forWord: "단어", index: $0, fontSize: 12) }
        let distinctRotations = Set(styles.map(\.rotationDegrees))
        XCTAssertGreaterThan(distinctRotations.count, 1)
    }

    func testRotationStaysWithinExpectedRange() {
        for i in 0..<50 {
            let style = CollageStyle.style(forWord: "테스트", index: i, fontSize: 12)
            XCTAssertGreaterThanOrEqual(style.rotationDegrees, -6)
            XCTAssertLessThanOrEqual(style.rotationDegrees, 6)
        }
    }
}
