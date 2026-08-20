import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

enum MaskPresetGroup: String, CaseIterable {
    case basic
    case landscape

    var displayName: String {
        switch self {
        case .basic: return "기본 도형"
        case .landscape: return "풍경"
        }
    }
}

/// Every preset is a hand-drawn vector shape. Photo-derived masks still
/// exist as a feature — a user's own uploaded photo goes through
/// `SubjectMaskGenerator` via `MaskSource.custom` — there just aren't any
/// bundled photos shipped as presets.
enum MaskPreset: String, CaseIterable, Identifiable {
    case circle, square, triangle, star
    case mountainIcon, house, river, sea

    var id: String { rawValue }

    var group: MaskPresetGroup {
        switch self {
        case .circle, .square, .triangle, .star: return .basic
        case .mountainIcon, .house, .river, .sea: return .landscape
        }
    }

    var displayName: String {
        switch self {
        case .circle: return "원"
        case .square: return "정사각형"
        case .triangle: return "삼각형"
        case .star: return "별"
        case .mountainIcon: return "산"
        case .house: return "집"
        case .river: return "강"
        case .sea: return "바다"
        }
    }

    /// The progression, in order: fill one shape completely and the next
    /// opens. Landscape shapes aren't on it — they're a different *kind*
    /// of picture, not a further rung on the same ladder, so gating them
    /// would read as the app withholding content rather than as progress.
    static let ladder: [MaskPreset] = [.circle, .square, .triangle, .star]

    /// The shape that must be filled before this one opens, or `nil` for
    /// anything available from the start.
    var unlockedByFilling: MaskPreset? {
        guard let index = Self.ladder.firstIndex(of: self), index > 0 else { return nil }
        return Self.ladder[index - 1]
    }

    /// Scales the fill text for this shape. Later rungs use finer text so
    /// each one takes more words than the last — without it the ladder
    /// gets *easier* partway through, because a shape's capacity follows
    /// how much of its own bounding box it covers and that runs 원 79% →
    /// 정사각형 97% → 삼각형 50% → 별 40%. Drawing the later shapes larger
    /// can't fix that: `MountainWordCloud` aspect-fits every mask to the
    /// canvas, so a star drawn at any source size renders identically.
    /// Finer text is the one knob that actually changes how much a shape
    /// holds — and it reads as the picture getting more detailed, which
    /// suits a later rung anyway.
    var textScale: CGFloat {
        switch self {
        case .circle, .square: return 1
        case .triangle: return 0.65
        case .star: return 0.52
        case .mountainIcon, .house, .river, .sea: return 1
        }
    }

    /// Only the sea currently animates — `phase` is ignored by every other
    /// (static) shape.
    var isAnimated: Bool { self == .sea }

    @MainActor
    fileprivate func renderVectorMask(phase: Double = 0) -> ImageMask? {
        switch self {
        case .circle:
            return ImageMask.render(Circle().fill(.black), size: CGSize(width: 320, height: 320))
        case .square:
            return ImageMask.render(RoundedRectangle(cornerRadius: 20).fill(.black), size: CGSize(width: 320, height: 320))
        case .triangle:
            return ImageMask.render(TriangleShape().fill(.black), size: CGSize(width: 320, height: 300))
        case .star:
            return ImageMask.render(StarShape().fill(.black), size: CGSize(width: 320, height: 320))
        case .mountainIcon:
            return ImageMask.render(MountainIconShape().fill(.black), size: CGSize(width: 320, height: 220))
        case .house:
            return ImageMask.render(HouseShape().fill(.black), size: CGSize(width: 320, height: 300))
        case .river:
            return ImageMask.render(RiverShape().fill(.black), size: CGSize(width: 320, height: 320))
        case .sea:
            return ImageMask.render(SeaShape(phase: phase).fill(.black), size: CGSize(width: 320, height: 320))
        }
    }

    /// How many words fill this shape, at the big window's size. Cached
    /// because it's fixed per shape (the mask is deterministic and the
    /// reference canvas never changes) and computing it renders a mask.
    @MainActor
    var wordsToFill: Int {
        if let cached = Self.fillCapacityCache[self] { return cached }
        guard let mask = renderVectorMask() else { return .max }
        let capacity = ShapeFillEstimator.capacity(
            mask: mask,
            canvas: CGSize(width: BigMountainView.canvasMinWidth, height: BigMountainView.canvasMinHeight),
            rowHeight: Self.measuredRowHeight(fontSize: MountainWordCloud.maxWordSize * textScale),
            averageWordWidth: Self.measuredWordWidth(fontSize: (MountainWordCloud.minWordSize + MountainWordCloud.maxWordSize) / 2 * textScale),
            minGap: MountainWordCloud.minGap * textScale
        )
        Self.fillCapacityCache[self] = capacity
        return capacity
    }

    /// Measured, not assumed: `MountainWordCloud` spaces rows by a real
    /// glyph's rendered height, which runs well above the font's point
    /// size (Korean ascenders/descenders are tall). Using the point size
    /// here instead would fit ~25% more rows on paper than the renderer
    /// ever draws, and every shape would look full long before the counter
    /// agreed.
    private static func measuredRowHeight(fontSize: CGFloat) -> CGFloat {
        Self.measure("가", fontSize: fontSize).height
    }

    /// A typical Korean word — three syllables, at the middle of the size
    /// range the renderer picks from.
    private static func measuredWordWidth(fontSize: CGFloat) -> CGFloat {
        Self.measure("단어들", fontSize: fontSize).width
    }

    private static func measure(_ text: String, fontSize: CGFloat) -> CGSize {
        let font = NSFont(descriptor: NSFont.systemFont(ofSize: fontSize).fontDescriptor.withDesign(.serif) ?? NSFont.systemFont(ofSize: fontSize).fontDescriptor, size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)
        return (text as NSString).size(withAttributes: [.font: font])
    }

    @MainActor
    private static var fillCapacityCache: [MaskPreset: Int] = [:]

    @MainActor
    func isUnlocked(wordsTyped: Int) -> Bool {
        guard let required = unlockedByFilling else { return true }
        return wordsTyped >= required.wordsToFill
    }
}

enum MaskSource: Equatable {
    case preset(MaskPreset)
    case custom(URL)

    var storageValue: String {
        switch self {
        case .preset(let preset): return "preset:\(preset.rawValue)"
        case .custom(let url): return "custom:\(url.path)"
        }
    }

    static func from(storageValue: String) -> MaskSource? {
        if storageValue.hasPrefix("preset:") {
            return MaskPreset(rawValue: String(storageValue.dropFirst("preset:".count))).map { .preset($0) }
        }
        if storageValue.hasPrefix("custom:") {
            return .custom(URL(fileURLWithPath: String(storageValue.dropFirst("custom:".count))))
        }
        return nil
    }
}

/// Owns the currently selected fill image and the `ImageMask` generated
/// from it, so any part of the UI can offer preset/custom-photo pickers
/// without duplicating the load-and-segment pipeline.
@MainActor
final class MaskStore: ObservableObject {
    @Published private(set) var mask: ImageMask?
    @Published private(set) var isLoading = false
    /// A slow, whole-shape vertical drift alongside the wave crest's own
    /// ripple — the crest geometry only ever redraws the top few rows (a
    /// mountain's-worth of static text below it never has a reason to
    /// change), so on its own the motion reads as "just the top wiggling".
    /// Shifting everything together by this same shared offset makes the
    /// whole body of text rise and fall as one piece, like a swell passing
    /// under the water rather than only its surface rippling.
    @Published private(set) var swellOffset: CGFloat = 0
    @Published private(set) var selection: MaskSource {
        didSet {
            UserDefaults.standard.set(selection.storageValue, forKey: Self.storageKey)
            reload()
        }
    }

    private static let storageKey = "TypingScape.maskSelection"
    private var generation = 0
    private var animationTask: Task<Void, Never>?
    /// How many views are currently displaying this mask (the menu bar
    /// popup, the big window — either, both, or neither at any moment).
    /// The animation loop would otherwise run forever in the background
    /// the moment an animated preset is picked, burning CPU all day in a
    /// menu bar app nobody's looking at.
    private var visibleConsumerCount = 0

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.storageKey),
           let source = MaskSource.from(storageValue: saved) {
            selection = source
        } else {
            selection = .preset(.mountainIcon)
        }
        reload()
    }

    /// The current shape's fill-text scale — 1 for an uploaded photo,
    /// which isn't on the progression ladder.
    var textScale: CGFloat {
        if case .preset(let preset) = selection { return preset.textScale }
        return 1
    }

    func select(_ source: MaskSource) {
        selection = source
    }

    func viewDidAppear() {
        visibleConsumerCount += 1
        if visibleConsumerCount == 1 { refreshAnimation() }
    }

    func viewDidDisappear() {
        visibleConsumerCount = max(0, visibleConsumerCount - 1)
        if visibleConsumerCount == 0 { refreshAnimation() }
    }

    private func reload() {
        generation += 1
        let source = selection

        // Vector shapes render instantly on the main actor — no need for
        // the background dispatch the photo/Vision pipeline needs. Every
        // preset is a vector shape; only a custom photo takes the slow path.
        if case .preset(let preset) = source {
            mask = preset.renderVectorMask()
            isLoading = false
            refreshAnimation()
            return
        }

        let thisGeneration = generation
        isLoading = true
        refreshAnimation()
        Task.detached(priority: .userInitiated) {
            let mask = Self.loadMask(for: source)
            await MainActor.run {
                guard self.generation == thisGeneration else { return } // a newer selection already superseded this
                self.mask = mask
                self.isLoading = false
            }
        }
    }

    /// Re-renders an animated vector preset on a slow, cheap cadence — a
    /// vector fill + pixel scan is fast enough that redoing it a few times
    /// a second doesn't need a background thread, unlike the photo
    /// pipeline. Stops as soon as nothing is showing it, or the selection
    /// moves off an animated preset.
    private func refreshAnimation() {
        animationTask?.cancel()
        animationTask = nil
        swellOffset = 0
        guard visibleConsumerCount > 0, case .preset(let preset) = selection, preset.isAnimated else { return }

        let thisGeneration = generation
        animationTask = Task { [weak self] in
            var phase = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard let self, self.generation == thisGeneration else { return }
                phase += 0.2
                self.mask = preset.renderVectorMask(phase: phase)
                // A slower multiple of the same phase — the whole body
                // drifts on a longer cycle than the crest ripple itself.
                self.swellOffset = CGFloat(sin(phase * 0.4)) * 5
            }
        }
    }

    /// Only ever reached for `.custom` — presets are all vector shapes and
    /// return earlier, on the main actor.
    nonisolated private static func loadMask(for source: MaskSource) -> ImageMask? {
        guard case .custom(let url) = source,
              let image = loadImage(url: url),
              let generated = SubjectMaskGenerator.generate(from: image)
        else { return nil }
        return ImageMask(cgImage: generated.silhouette, densityImage: generated.density)
    }

    nonisolated private static func loadImage(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
