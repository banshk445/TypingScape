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
