import SwiftUI

/// Deterministic per-word "cut from a magazine" styling — a chip color/ink
/// pair, a slight rotation, a font choice, and a case treatment — so the
/// same word at the same position always renders the same way (no flicker
/// on redraw) without needing to store per-word state anywhere.
enum CollageStyle {
    /// (chip background, ink text color) pairs pulled from vintage
    /// magazine-cutout / ransom-note references: black, deep red, mustard,
    /// raw paper, navy, sage.
    private static let chips: [(chip: Color, ink: Color)] = [
        (Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1C / 255), .white),
        (Color(red: 0x8B / 255, green: 0x1E / 255, blue: 0x1E / 255), Theme.paperBase),
        (Color(red: 0xD4 / 255, green: 0xA5 / 255, blue: 0x2A / 255), Theme.ink),
        (Color(red: 0xEF / 255, green: 0xE6 / 255, blue: 0xD2 / 255), Theme.ink),
        (Color(red: 0x1F / 255, green: 0x3A / 255, blue: 0x5C / 255), Theme.paperBase),
        (Color(red: 0x3E / 255, green: 0x5C / 255, blue: 0x4E / 255), Theme.paperBase),
    ]

    struct Style {
        let chip: Color
        let ink: Color
        let rotationDegrees: Double
        let font: Font
        let displayWord: String
    }

    static func style(forWord word: String, index: Int, fontSize: CGFloat) -> Style {
        let h = hash(index)
        let (chip, ink) = chips[h % chips.count]
        let rotationDegrees = Double((h / chips.count) % 13) - 6 // -6...6
        let isBold = (h / (chips.count * 13)) % 2 == 0
        let isSerif = (h / (chips.count * 13 * 2)) % 3 != 0 // mostly serif, sometimes bold sans
        let font: Font = isSerif
            ? Theme.serif(fontSize, weight: isBold ? .bold : .medium)
            : .system(size: fontSize * 0.95, weight: isBold ? .heavy : .semibold)
        let displayWord = (h % 4 == 0) ? word.uppercased() : word
        return Style(chip: chip, ink: ink, rotationDegrees: rotationDegrees, font: font, displayWord: displayWord)
    }

    private static func hash(_ x: Int) -> Int {
        var h = x &* 2_654_435_761
        h = (h ^ (h >> 15)) &* 0x85EBCA6B
        return abs(h ^ (h >> 13))
    }
}
