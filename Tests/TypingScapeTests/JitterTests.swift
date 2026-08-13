import XCTest
@testable import TypingScape

final class JitterTests: XCTestCase {
    func testStaysWithinAmplitude() {
        for seed in 0..<200 {
            let value = Jitter.offset(seed: seed, amplitude: 3)
            XCTAssertGreaterThanOrEqual(value, -3)
            XCTAssertLessThanOrEqual(value, 3)
        }
    }

    func testIsDeterministicForTheSameSeed() {
        XCTAssertEqual(Jitter.offset(seed: 42, amplitude: 5), Jitter.offset(seed: 42, amplitude: 5))
    }

    func testVariesAcrossDifferentSeeds() {
        let values = Set((0..<20).map { Jitter.offset(seed: $0, amplitude: 5) })
        XCTAssertGreaterThan(values.count, 1)
    }
}
