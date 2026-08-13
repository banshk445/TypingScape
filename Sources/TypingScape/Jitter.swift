import CoreGraphics

/// A deterministic pseudo-random offset in `-amplitude...amplitude` — the
/// same `seed` always produces the same value (no flicker on redraw), used
/// to nudge a word's baseline or a row's spacing off a perfectly ruled grid
/// so a hand-set/collage feel instead of a spreadsheet-straight one.
enum Jitter {
    static func offset(seed: Int, amplitude: CGFloat) -> CGFloat {
        var h = UInt64(bitPattern: Int64(seed)) &* 2_654_435_761
        h = (h ^ (h >> 15)) &* 0x85EBCA6B
        h ^= h >> 13
        let unit = Double(h % 10_000) / 10_000.0 // 0..<1
        return CGFloat(unit * 2 - 1) * amplitude // -amplitude...amplitude
    }
}
