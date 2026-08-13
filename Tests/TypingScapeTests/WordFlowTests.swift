import XCTest
@testable import TypingScape

final class WordFlowTests: XCTestCase {
    func testInterleavesInsteadOfClumping() {
        let flow = WordFlow.build(from: [(word: "a", count: 3), (word: "b", count: 1)])
        // Round-robin: a,b, then a again (b already exhausted), then a again.
        XCTAssertEqual(flow.map(\.word), ["a", "b", "a", "a"])
    }

    func testCapsRepeatsPerWord() {
        let flow = WordFlow.build(from: [(word: "a", count: 100)], repeatCap: 6)
        XCTAssertEqual(flow.count, 6)
    }

    func testEmptyInputProducesEmptyFlow() {
        XCTAssertTrue(WordFlow.build(from: []).isEmpty)
    }

    func testEachEntryKeepsItsOriginalCountNotTheCappedRemaining() {
        let flow = WordFlow.build(from: [(word: "a", count: 100)], repeatCap: 6)
        XCTAssertTrue(flow.allSatisfy { $0.count == 100 })
    }
}
