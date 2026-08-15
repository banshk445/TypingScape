import SwiftUI

/// Shows the mask's raw silhouette (what `MountainWordCloud` uses to
/// place words) and density (what it uses to render their opacity) side
/// by side, straight from `ImageMask`, before any word ever touches
/// them. Lets you tell at a glance whether a bad result comes from mask
/// generation (`SubjectMaskGenerator`) or from placement/rendering
/// against an otherwise-correct mask — a full silhouette with a bad
/// render points at `MountainWordCloud`; a wrong/empty silhouette points
/// at the generator.
struct MaskDebugView: View {
    @ObservedObject var maskStore: MaskStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("마스크 디버그")
                    .font(Theme.serif(17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkSecondary)
                }
                .buttonStyle(.plain)
            }

            if let mask = maskStore.mask {
                Text("전체 크기 \(Int(mask.size.width))×\(Int(mask.size.height)) · 내용 영역 \(String(format: "%.0f%% × %.0f%%", mask.contentBoundsFraction.width * 100, mask.contentBoundsFraction.height * 100))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSecondary)

                HStack(alignment: .top, spacing: 16) {
                    preview(title: "실루엣 · 배치 기준", image: mask.croppedToContent())
                    preview(title: "농도 · 렌더링 진하기", image: mask.croppedDensityContent())
                }
            } else {
                Text("현재 로드된 마스크가 없어요")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(Theme.paperCard)
    }

    @ViewBuilder
    private func preview(title: String, image: CGImage?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Theme.captionLabel(title)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 240)
                    .background(Theme.paperBase)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.border))
            } else {
                Text("생성 실패 (nil)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
    }
}
