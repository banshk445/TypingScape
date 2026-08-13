import SwiftUI
import XCTest
@testable import TypingScape

final class LandscapeShapesTests: XCTestCase {
    func testSeaShapePhaseChangesTheWaveProfile() {
        // At phase 0, one hump's own offset (i * .pi/2) lands it exactly at
        // sin == 1 — the global max across all 4 humps. At .pi/4, every
        // hump sits at sin(.pi/4 + k*.pi/2) == +-sqrt(2)/2, so the global
        // max (and the bounding box's top edge) is measurably lower.
        let rect = CGRect(x: 0, y: 0, width: 320, height: 320)
        let atRest = SeaShape(phase: 0).path(in: rect).boundingRect
        let midCycle = SeaShape(phase: .pi / 4).path(in: rect).boundingRect
        XCTAssertNotEqual(atRest.minY, midCycle.minY, accuracy: 0.01)
    }

    func testSeaShapeStaysClosedAndFilledToTheBottom() {
        let rect = CGRect(x: 0, y: 0, width: 320, height: 320)
        for phase in stride(from: 0.0, to: 2 * Double.pi, by: 0.5) {
            let bounds = SeaShape(phase: phase).path(in: rect).boundingRect
            XCTAssertEqual(bounds.maxY, rect.height, accuracy: 0.01)
        }
    }
}
