import XCTest
@testable import TypingScape

final class SpiralPlacerTests: XCTestCase {
    private func squareArena(side: CGFloat = 100) -> SpiralPlacer {
        SpiralPlacer(canvasSize: CGSize(width: side, height: side)) { point in
            point.x >= 0 && point.x <= side && point.y >= 0 && point.y <= side
        }
    }

    func testFirstPlacementLandsAtSeed() {
        var placer = squareArena()
        let seed = CGPoint(x: 50, y: 50)
        let rect = placer.place(size: CGSize(width: 10, height: 10), near: seed)
        XCTAssertNotNil(rect)
        XCTAssertEqual(rect!.midX, seed.x, accuracy: 0.01)
        XCTAssertEqual(rect!.midY, seed.y, accuracy: 0.01)
    }

    func testSecondOverlappingPlacementMovesAway() {
        var placer = squareArena()
        let seed = CGPoint(x: 50, y: 50)
        let first = placer.place(size: CGSize(width: 20, height: 20), near: seed)!
        let second = placer.place(size: CGSize(width: 20, height: 20), near: seed)!
        XCTAssertFalse(first.intersects(second))
    }

    func testKeepsAGapBetweenAdjacentPlacements() {
        var placer = squareArena()
        let seed = CGPoint(x: 50, y: 50)
        let first = placer.place(size: CGSize(width: 10, height: 10), near: seed)!
        let second = placer.place(size: CGSize(width: 10, height: 10), near: seed)!
        // Merely touching (zero gap) rects would visually glue two words
        // together, so require actual clearance, not just non-overlap.
        XCTAssertFalse(first.insetBy(dx: -3, dy: -3).intersects(second))
    }

    func testReturnsNilWhenNothingFits() {
        var placer = squareArena(side: 10)
        let oversized = placer.place(size: CGSize(width: 50, height: 50), near: CGPoint(x: 5, y: 5))
        XCTAssertNil(oversized)
    }

    func testStaysInsideTheGivenRegion() {
        // only the right half of the arena is "inside"
        var placer = SpiralPlacer(canvasSize: CGSize(width: 100, height: 100)) { point in
            point.x >= 50 && point.x <= 100 && point.y >= 0 && point.y <= 100
        }
        let rect = placer.place(size: CGSize(width: 10, height: 10), near: CGPoint(x: 40, y: 50))
        XCTAssertNotNil(rect)
        XCTAssertGreaterThanOrEqual(rect!.minX, 50)
    }
}
