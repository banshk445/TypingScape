import XCTest
@testable import TypingScape

@MainActor
final class ShapeProgressionTests: XCTestCase {
    func testLadderGetsHarderEveryRung() throws {
        // The reason `textScale` exists: raw shape area runs 원 → 정사각형
        // → 삼각형 → 별 as 79% → 97% → 50% → 40%, so without correction the
        // ladder gets *easier* after the second rung. Filling one shape
        // must always take more words than the one before it.
        let capacities = MaskPreset.ladder.map(\.wordsToFill)
        for (previous, next) in zip(capacities, capacities.dropFirst()) {
            XCTAssertGreaterThan(next, previous, "ladder capacities: \(capacities)")
        }
    }

    func testFirstRungIsOpenAndOthersStartLocked() {
        XCTAssertTrue(MaskPreset.circle.isUnlocked(wordsTyped: 0))
        XCTAssertFalse(MaskPreset.square.isUnlocked(wordsTyped: 0))
        XCTAssertFalse(MaskPreset.triangle.isUnlocked(wordsTyped: 0))
        XCTAssertFalse(MaskPreset.star.isUnlocked(wordsTyped: 0))
    }

    func testAShapeOpensExactlyWhenThePreviousOneIsFull() {
        let needed = MaskPreset.circle.wordsToFill
        XCTAssertFalse(MaskPreset.square.isUnlocked(wordsTyped: needed - 1))
        XCTAssertTrue(MaskPreset.square.isUnlocked(wordsTyped: needed))
    }

    func testLandscapeShapesAreNeverLocked() {
        for preset in MaskPreset.allCases where preset.group == .landscape {
            XCTAssertNil(preset.unlockedByFilling, "\(preset) should not be on the ladder")
            XCTAssertTrue(preset.isUnlocked(wordsTyped: 0))
        }
    }

    func testCapacitiesAreWithinAReachableRange() throws {
        // A gate nobody reaches is the same as a shape that doesn't exist.
        for preset in MaskPreset.ladder {
            let capacity = preset.wordsToFill
            XCTAssertGreaterThan(capacity, 0, "\(preset) reported no capacity")
            XCTAssertLessThan(capacity, 20_000, "\(preset) needs \(capacity) words — unreachable")
        }
    }
}
