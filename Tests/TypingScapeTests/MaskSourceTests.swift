import XCTest
@testable import TypingScape

final class MaskSourceTests: XCTestCase {
    func testPresetRoundTripsThroughStorage() {
        let source = MaskSource.preset(.albumCover)
        let restored = MaskSource.from(storageValue: source.storageValue)
        XCTAssertEqual(restored, source)
    }

    func testCustomURLRoundTripsThroughStorage() {
        let source = MaskSource.custom(URL(fileURLWithPath: "/Users/banshk/Pictures/photo.jpg"))
        let restored = MaskSource.from(storageValue: source.storageValue)
        XCTAssertEqual(restored, source)
    }

    func testUnrecognizedStorageValueReturnsNil() {
        XCTAssertNil(MaskSource.from(storageValue: "garbage"))
        XCTAssertNil(MaskSource.from(storageValue: "preset:not-a-real-preset"))
    }
}
