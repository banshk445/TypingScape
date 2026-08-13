import CoreGraphics
import XCTest
@testable import TypingScape

final class ImageMaskTests: XCTestCase {
    /// Builds a 4x2 test bitmap: left half fully opaque, right half fully
    /// transparent — no SwiftUI/ImageRenderer involved, just CoreGraphics,
    /// so this exercises `ImageMask`'s pixel sampling directly.
    private func halfOpaqueMask() -> ImageMask {
        let width = 4, height = 2
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<2 {
                let i = (y * width + x) * 4
                data[i] = 0; data[i + 1] = 0; data[i + 2] = 0; data[i + 3] = 255
            }
        }
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ImageMask(cgImage: context.makeImage()!)!
    }

    func testInsideOpaqueRegion() {
        let mask = halfOpaqueMask()
        XCTAssertTrue(mask.isInside(CGPoint(x: 0, y: 0)))
        XCTAssertTrue(mask.isInside(CGPoint(x: 1, y: 1)))
    }

    func testOutsideTransparentRegion() {
        let mask = halfOpaqueMask()
        XCTAssertFalse(mask.isInside(CGPoint(x: 2, y: 0)))
        XCTAssertFalse(mask.isInside(CGPoint(x: 3, y: 1)))
    }

    func testOutsideBounds() {
        let mask = halfOpaqueMask()
        XCTAssertFalse(mask.isInside(CGPoint(x: -1, y: 0)))
        XCTAssertFalse(mask.isInside(CGPoint(x: 4, y: 0)))
    }

    func testFractionalSampling() {
        let mask = halfOpaqueMask()
        XCTAssertTrue(mask.isInside(atFraction: CGPoint(x: 0.1, y: 0.5)))
        XCTAssertFalse(mask.isInside(atFraction: CGPoint(x: 0.9, y: 0.5)))
    }

    func testCentroidIsCenterOfTheOpaqueRegion() {
        // Opaque pixels are x=0,1 (of width 4) at both y=0,1 (of height 2):
        // mean x = 0.5 -> fraction 0.5/4 = 0.125; mean y = 0.5 -> fraction 0.5/2 = 0.25.
        let mask = halfOpaqueMask()
        XCTAssertEqual(mask.centroidFraction.x, 0.125, accuracy: 0.01)
        XCTAssertEqual(mask.centroidFraction.y, 0.25, accuracy: 0.01)
    }

    func testBottomFractionUsesOnlyTheLowestRow() {
        // Top row (y=0) opaque on the left (x=0,1); bottom row (y=1) opaque
        // on the right (x=2,3) — so centroid.x sits in the middle, but
        // bottomFraction.x should follow only the bottom row's pixels.
        let width = 4, height = 2
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for (y, xs) in [(0, [0, 1]), (1, [2, 3])] {
            for x in xs {
                let i = (y * width + x) * 4
                data[i + 3] = 255
            }
        }
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let mask = ImageMask(cgImage: context.makeImage()!)!

        XCTAssertEqual(mask.bottomFraction.x, 0.625, accuracy: 0.01) // (2+3)/2 / 4
        XCTAssertEqual(mask.bottomFraction.y, 0.5, accuracy: 0.01) // row 1 of 2
    }

    func testHorizontalExtentsMatchesTheOpaqueSpanAtThatRow() {
        // halfOpaqueMask is opaque at x=0,1 for every row.
        let mask = halfOpaqueMask()
        let extents = mask.horizontalExtents(atFractionY: 0.5)
        XCTAssertEqual(extents.count, 1)
        XCTAssertEqual(extents[0].0, 0, accuracy: 0.01)
        XCTAssertEqual(extents[0].1, 0.5, accuracy: 0.01) // (maxX+1)/width = 2/4
    }

    func testHorizontalExtentsIsEmptyWhereRowHasNoFill() {
        let width = 4, height = 2
        var data = [UInt8](repeating: 0, count: width * height * 4) // fully transparent
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let mask = ImageMask(cgImage: context.makeImage()!)!
        XCTAssertTrue(mask.horizontalExtents(atFractionY: 0.5).isEmpty)
    }

    func testHorizontalExtentsReturnsEachSeparateRunNotJustTheLongest() {
        // 20x2 image: two separate opaque runs on the same row — a short
        // one at x=0...2 and a longer one at x=10...18 — separated by a
        // transparent gap. Both runs are real fill region and should each
        // come back, not just the longer one and not a bridged span that
        // (wrongly) includes the gap.
        let width = 20, height = 2
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<3 { data[(y * width + x) * 4 + 3] = 255 }
            for x in 10..<18 { data[(y * width + x) * 4 + 3] = 255 }
        }
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let mask = ImageMask(cgImage: context.makeImage()!)!
        let extents = mask.horizontalExtents(atFractionY: 0.5)
        XCTAssertEqual(extents.count, 2)
        XCTAssertEqual(extents[0].0, 0, accuracy: 0.01)
        XCTAssertEqual(extents[0].1, 3.0 / 20.0, accuracy: 0.01)
        XCTAssertEqual(extents[1].0, 10.0 / 20.0, accuracy: 0.01)
        XCTAssertEqual(extents[1].1, 18.0 / 20.0, accuracy: 0.01)
    }

    func testContentBoundsExcludesBlankMargin() {
        // 10x10 image, opaque only in the center 4x4 block (x,y = 3...6).
        let width = 10, height = 10
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 3...6 {
            for x in 3...6 {
                data[(y * width + x) * 4 + 3] = 255
            }
        }
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let mask = ImageMask(cgImage: context.makeImage()!)!

        XCTAssertEqual(mask.contentBoundsFraction.minX, 0.3, accuracy: 0.01)
        XCTAssertEqual(mask.contentBoundsFraction.minY, 0.3, accuracy: 0.01)
        XCTAssertEqual(mask.contentBoundsFraction.width, 0.4, accuracy: 0.01)
        XCTAssertEqual(mask.contentBoundsFraction.height, 0.4, accuracy: 0.01)

        let cropped = mask.croppedToContent()!
        XCTAssertEqual(cropped.width, 4)
        XCTAssertEqual(cropped.height, 4)
    }

    func testTintedCroppedContentAppliesTheGivenColor() {
        let mask = halfOpaqueMask()
        let tinted = mask.tintedCroppedContent(red: 10, green: 20, blue: 30)!
        let context = CGContext(
            data: nil, width: tinted.width, height: tinted.height, bitsPerComponent: 8,
            bytesPerRow: tinted.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(tinted, in: CGRect(x: 0, y: 0, width: tinted.width, height: tinted.height))
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(pixels[0], 10)
        XCTAssertEqual(pixels[1], 20)
        XCTAssertEqual(pixels[2], 30)
    }
}
