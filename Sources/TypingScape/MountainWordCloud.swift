import SwiftUI

/// Fills the mask like justified text clipped to its silhouette: row by
/// row from the bottom up, each row's words spread with even gaps so the
/// row spans edge-to-edge — the shape reads purely from how the words are
/// packed, no separate outline drawn.
struct MountainWordCloud: View {
    let topWords: [(word: String, count: Int)]
    let mask: ImageMask?
    var style: WordCloudStyle = .editorial
    /// Shifts the whole fill vertically — driven by `MaskStore`'s animated
    /// presets so the entire body of text drifts as one piece alongside
    /// the mask's own shape change, instead of only the boundary moving.
    var swellOffset: CGFloat = 0

    var body: some View {
        let flow = WordFlow.build(from: topWords)
        let counts = topWords.map(\.count)
        let minCount = counts.min() ?? 1
        let maxCount = counts.max() ?? 1
        return Canvas { context, size in
            guard let mask, !flow.isEmpty else { return }
            context.translateBy(x: 0, y: swellOffset)
            let bounds = mask.contentBoundsFraction
            let contentSize = CGSize(width: bounds.width * mask.size.width, height: bounds.height * mask.size.height)
            let maskRect = AspectFit.rect(fitting: contentSize, in: size)

            // A word typed often should visibly outgrow a one-off word, not
            // render at the same size — the row height has to fit the
            // largest size this range can produce, which costs some of the
            // fine row-to-row resolution the shape's tips relied on.
            let minWordSize: CGFloat = 8
            let maxWordSize: CGFloat = 15
            let rowHeight = maxWordSize * 0.9
            let minGap: CGFloat = 4
            let rowCount = max(1, Int(maskRect.height / rowHeight))

            // Cycles through `flow` as many times as it takes to cover
            // every row — the point is to fill the whole shape, not to
            // stop once today's (possibly short) word list runs out once.
            var wordIndex = 0

            struct Placed { let resolved: GraphicsContext.ResolvedText; let size: CGSize; let rotation: Double; let chipColor: Color?; let jitterY: CGFloat }

            // Fills one contiguous span of a row — a row can have more than
            // one (a sea's separate wave crests, a star's two feet), and
            // each needs its own justified pass so no span is left blank.
            func fillSpan(rowY: CGFloat, minX: CGFloat, maxX: CGFloat) {
                let rowWidth = maxX - minX
                // Near a shape's narrow extremities (a star's point, a
                // mountain's peak) not even the smallest frequency size
                // fits — shrink the cap itself instead of skipping the row
                // outright, so text traces much closer to the actual tip.
                guard let spanFontCap = AdaptiveFontSize.fontSize(forRowWidth: rowWidth, standard: maxWordSize, minimum: 5) else { return }

                // Pass 1: greedily collect whichever words fit this span,
                // measuring at a nominal minimum gap. Each word's size
                // comes from how often it was typed today, capped by
                // whatever actually fits this span.
                var spanWords: [Placed] = []
                var accumulated: CGFloat = 0
                while true {
                    let entry = flow[wordIndex % flow.count]
                    let word = entry.word
                    let naturalSize = FrequencyFontSize.fontSize(
                        forCount: entry.count, minCount: minCount, maxCount: maxCount, minSize: minWordSize, maxSize: maxWordSize
                    )
                    let wordFontSize = min(naturalSize, spanFontCap)
                    let resolved: GraphicsContext.ResolvedText
                    let extraPad: CGFloat
                    let rotation: Double
                    let chipColor: Color?
                    switch style {
                    case .collage:
                        let collage = CollageStyle.style(forWord: word, index: wordIndex, fontSize: wordFontSize)
                        resolved = context.resolve(Text(collage.displayWord).font(collage.font).foregroundColor(collage.ink))
                        extraPad = 6
                        rotation = collage.rotationDegrees
                        chipColor = collage.chip
                    case .editorial:
                        resolved = context.resolve(Text(word).font(Theme.serif(wordFontSize, weight: .medium)).foregroundColor(Theme.ink))
                        extraPad = 0
                        rotation = 0
                        chipColor = nil
                    }
                    let baseSize = resolved.measure(in: size)
                    let wordSize = CGSize(width: baseSize.width + extraPad, height: baseSize.height + extraPad * 0.7)
                    let needed = accumulated + (spanWords.isEmpty ? 0 : minGap) + wordSize.width
                    guard needed <= rowWidth else { break }
                    accumulated = needed
                    // A word sitting exactly on the row's ruled line, every
                    // row perfectly evenly spaced, reads as a spreadsheet
                    // rather than something hand-set — a small per-word
                    // baseline wobble breaks that up.
                    let jitterY = Jitter.offset(seed: wordIndex, amplitude: 2)
                    spanWords.append(Placed(resolved: resolved, size: wordSize, rotation: rotation, chipColor: chipColor, jitterY: jitterY))
                    wordIndex += 1
                }
                guard !spanWords.isEmpty else { return }

                // Pass 2: justify — spread the leftover space evenly across
                // the gaps so the span's first/last word touch minX/maxX.
                let totalWordWidth = spanWords.reduce(0) { $0 + $1.size.width }
                let gapCount = spanWords.count - 1
                let gap = gapCount > 0 ? (rowWidth - totalWordWidth) / CGFloat(gapCount) : 0

                var cursorX = spanWords.count == 1 ? minX + (rowWidth - spanWords[0].size.width) / 2 : minX
                for placed in spanWords {
                    let center = CGPoint(x: cursorX + placed.size.width / 2, y: rowY + placed.jitterY)
                    if let chipColor = placed.chipColor {
                        context.drawLayer { layer in
                            layer.translateBy(x: center.x, y: center.y)
                            layer.rotate(by: .degrees(placed.rotation))
                            layer.translateBy(x: -center.x, y: -center.y)
                            let chipRect = CGRect(
                                x: center.x - placed.size.width / 2, y: center.y - placed.size.height / 2,
                                width: placed.size.width, height: placed.size.height
                            )
                            layer.fill(Path(roundedRect: chipRect, cornerRadius: 2), with: .color(chipColor))
                            layer.draw(placed.resolved, at: center, anchor: .center)
                        }
                    } else {
                        context.draw(placed.resolved, at: center, anchor: .center)
                    }
                    cursorX += placed.size.width + gap
                }
            }

            for rowFromBottom in 0..<rowCount {
                // Rows this evenly spaced, row after row, is the other half
                // of the "ruled grid" look — nudging each one keeps them
                // from crossing (bounded well under half the row height)
                // while breaking up the rhythm.
                let rowJitter = Jitter.offset(seed: rowFromBottom, amplitude: rowHeight * 0.22)
                let rowY = maskRect.maxY - (CGFloat(rowFromBottom) + 0.5) * rowHeight + rowJitter
                guard rowY >= maskRect.minY else { break }
                // Map this row's position within the cropped content back to
                // the mask's own full-image fraction space before sampling.
                let contentFy = (rowY - maskRect.minY) / maskRect.height
                let fullFy = bounds.minY + contentFy * bounds.height
                let edgeInset = max(4, maskRect.width * 0.006)
                for fullExtent in mask.horizontalExtents(atFractionY: fullFy) {
                    let contentMinFx = (fullExtent.0 - bounds.minX) / bounds.width
                    let contentMaxFx = (fullExtent.1 - bounds.minX) / bounds.width
                    let minX = maskRect.minX + contentMinFx * maskRect.width + edgeInset
                    let maxX = maskRect.minX + contentMaxFx * maskRect.width - edgeInset
                    fillSpan(rowY: rowY, minX: minX, maxX: maxX)
                }
            }
        }
    }
}
