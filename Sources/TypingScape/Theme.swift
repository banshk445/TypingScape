import AppKit
import SwiftUI

extension Color {
    /// A `Color` that resolves to `light` or `dark` based on the *effective*
    /// appearance at draw time — including a view's own `.preferredColorScheme`
    /// override, not just the system setting. This is what lets picking the
    /// "다크" background style flip every themed color automatically, without
    /// threading a palette through every view and ButtonStyle by hand.
    init(light: Color, dark: Color) {
        self.init(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }
}

/// Paper/editorial direction: warm off-white "paper" surface with a subtle
/// grain texture, ink-black text and controls, New York (Apple's serif,
/// selected via SwiftUI's `.serif` design — the same family Apple News/
/// Books use) standing in for a magazine display face. Each color is
/// light/dark adaptive so the "다크" background style (which sets
/// `.preferredColorScheme(.dark)`) flips them automatically.
enum Theme {
    static let paperBase = Color(
        light: Color(red: 0xFD / 255, green: 0xFB / 255, blue: 0xF7 / 255),
        dark: Color(red: 0x16 / 255, green: 0x16 / 255, blue: 0x1A / 255)
    )
    static let paperCard = Color(
        light: Color(red: 0xF6 / 255, green: 0xF3 / 255, blue: 0xEC / 255),
        dark: Color(red: 0x22 / 255, green: 0x22 / 255, blue: 0x27 / 255)
    )
    static let border = Color(
        light: Color(red: 0xE1 / 255, green: 0xDC / 255, blue: 0xCF / 255),
        dark: Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x40 / 255)
    )
    static let ink = Color(
        light: Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255),
        dark: Color(red: 0xF2 / 255, green: 0xF0 / 255, blue: 0xEC / 255)
    )
    static let inkSecondary = Color(
        light: Color(red: 0x6B / 255, green: 0x6B / 255, blue: 0x63 / 255),
        dark: Color(red: 0x9A / 255, green: 0x9A / 255, blue: 0x93 / 255)
    )

    static let cardCornerRadius: CGFloat = 4
    static let controlCornerRadius: CGFloat = 3

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Small tracked-caps tag over a control group ("모양", "배경") — a
    /// magazine spec label, not a form field label.
    static func captionLabel(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.4)
            .foregroundColor(Theme.inkSecondary)
    }

    /// "<label> <N>개 단어 입력" with the count set in a heavier serif
    /// weight — reads like a byline stat, not a UI label. `label` defaults
    /// to "오늘" but takes a past date's own label when browsing history.
    static func wordCountText(_ count: Int, label: String = "오늘", size: CGFloat = 12) -> Text {
        Text("\(label) ").font(.system(size: size)).foregroundColor(Theme.inkSecondary)
            + Text("\(count)").font(Theme.serif(size + 1, weight: .semibold)).foregroundColor(Theme.ink)
            + Text("개 단어 입력").font(.system(size: size)).foregroundColor(Theme.inkSecondary)
    }
}

/// Fine, static grain rendered once into a small tile and repeated — a
/// cheap stand-in for real paper texture without a bundled image asset.
private struct NoiseTile: View {
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            while x < size.width {
                var y: CGFloat = 0
                while y < size.height {
                    let h = PaperTexture.hash(Int(x), Int(y))
                    if h % 5 == 0 {
                        let opacity = Double(h % 6) / 90.0 + 0.015
                        context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.black.opacity(opacity)))
                    }
                    y += 2
                }
                x += 2
            }
        }
    }
}

enum PaperTexture {
    @MainActor
    static let image: CGImage? = {
        let renderer = ImageRenderer(content: NoiseTile().frame(width: 96, height: 96))
        renderer.scale = 2
        return renderer.cgImage
    }()

    /// Deterministic per-cell "randomness" so the grain is stable across
    /// redraws instead of flickering (no `Random`/`Date` involved).
    fileprivate static func hash(_ x: Int, _ y: Int) -> Int {
        var h = x &* 374_761_393 &+ y &* 668_265_263
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return abs(h ^ (h >> 16)) % 100
    }
}

/// The app's background: paper color + tiled grain.
struct PaperBackground: View {
    var body: some View {
        ZStack {
            Theme.paperBase
            if let cgImage = PaperTexture.image {
                Image(decorative: cgImage, scale: 2)
                    .resizable(resizingMode: .tile)
                    .opacity(0.6)
            }
        }
    }
}

/// Irregular scan-grain (same generator as the paper texture, denser/
/// higher-contrast) — a photocopied-newspaper speckle, not a regular
/// print halftone dot grid.
private struct ScanGrainTile: View {
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            while x < size.width {
                var y: CGFloat = 0
                while y < size.height {
                    let h = PaperTexture.hash(Int(x), Int(y))
                    if h % 3 == 0 {
                        let opacity = Double(h % 10) / 60.0 + 0.02
                        context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.black.opacity(opacity)))
                    }
                    y += 1.5
                }
                x += 1.5
            }
        }
    }
}

enum NewsprintTexture {
    @MainActor
    static let tileImage: CGImage? = {
        let renderer = ImageRenderer(content: ScanGrainTile().frame(width: 96, height: 96))
        renderer.scale = 2
        return renderer.cgImage
    }()
}

/// Gray scanned-newspaper base with mottled soft shadow patches standing
/// in for uneven light across a crumpled page — patches, not straight
/// crease lines, since real creases rarely read as clean diagonals.
struct NewsprintBackground: View {
    private static let baseTone = Color(red: 0xD8 / 255, green: 0xD8 / 255, blue: 0xD6 / 255)
    private static let wrinkleSpots: [(x: CGFloat, y: CGFloat, radius: CGFloat, opacity: Double)] = [
        (0.12, 0.18, 260, 0.10), (0.68, 0.10, 300, 0.08), (0.42, 0.5, 380, 0.09),
        (0.88, 0.55, 320, 0.10), (0.22, 0.82, 340, 0.08), (0.62, 0.88, 300, 0.09),
        (0.5, 0.15, 220, 0.06), (0.05, 0.55, 260, 0.07),
    ]

    var body: some View {
        ZStack {
            Self.baseTone
            if let cgImage = NewsprintTexture.tileImage {
                Image(decorative: cgImage, scale: 2)
                    .resizable(resizingMode: .tile)
                    .opacity(0.7)
            }
            GeometryReader { geo in
                ZStack {
                    ForEach(Array(Self.wrinkleSpots.enumerated()), id: \.offset) { _, spot in
                        RadialGradient(
                            colors: [Color.black.opacity(spot.opacity), Color.black.opacity(0)],
                            center: .center, startRadius: 0, endRadius: spot.radius
                        )
                        .frame(width: spot.radius * 2, height: spot.radius * 2)
                        .position(x: geo.size.width * spot.x, y: geo.size.height * spot.y)
                    }
                }
            }
            .blendMode(.multiply)
        }
    }
}

/// Plain dark surface — no paper grain, since this is a general "dark
/// mode" rather than another texture to mimic.
struct DarkBackground: View {
    var body: some View {
        Theme.paperBase
    }
}

struct ThemedBackground: View {
    let style: BackgroundStyle

    var body: some View {
        switch style {
        case .paper: PaperBackground()
        case .newsprint: NewsprintBackground()
        case .dark: DarkBackground()
        }
    }
}

/// Solid ink button for the primary action ("크게 보기") — a black button
/// on cream paper is the classic editorial "Subscribe" affordance.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Theme.paperBase)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.controlCornerRadius).fill(Theme.ink.opacity(configuration.isPressed ? 0.75 : 1)))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Card-style toggle for the preset/photo picker — filled ink when
/// selected, outlined otherwise.
struct SelectableButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isSelected ? Theme.paperBase : Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Theme.controlCornerRadius).fill(isSelected ? Theme.ink : Theme.paperCard))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlCornerRadius).strokeBorder(Theme.border, lineWidth: isSelected ? 0 : 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Quiet text-only button for low-emphasis actions ("종료").
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.inkSecondary.opacity(configuration.isPressed ? 0.6 : 1))
    }
}

/// The word-cloud/preview surface — paper card, hairline border.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: Theme.cardCornerRadius).fill(Theme.paperCard))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardCornerRadius).strokeBorder(Theme.border))
    }
}

extension View {
    func themedCard() -> some View { modifier(CardBackground()) }
}
