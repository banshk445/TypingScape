import XCTest
@testable import TypingScape

final class MaskPresetUnlockTests: XCTestCase {
    func testCircleIsAvailableFromTheStart() {
        XCTAssertTrue(MaskPreset.circle.isUnlocked(bestDailyWordCount: 0))
    }

    func testBasicShapesUnlockInOrder() {
        // The whole point of the progression: each rung opens strictly
        // after the one before it.
        let ladder: [MaskPreset] = [.circle, .square, .triangle, .star]
        let thresholds = ladder.map(\.unlockThreshold)
        XCTAssertEqual(thresholds, thresholds.sorted())
        XCTAssertEqual(Set(thresholds).count, thresholds.count, "each rung needs its own threshold")
    }

    func testShapeUnlocksExactlyAtItsThreshold() {
        let star = MaskPreset.star
        XCTAssertFalse(star.isUnlocked(bestDailyWordCount: star.unlockThreshold - 1))
        XCTAssertTrue(star.isUnlocked(bestDailyWordCount: star.unlockThreshold))
    }

    func testLandscapeShapesAreNeverLocked() {
        for preset in MaskPreset.allCases where preset.group == .landscape {
            XCTAssertTrue(preset.isUnlocked(bestDailyWordCount: 0), "\(preset) should not be gated")
        }
    }
}
