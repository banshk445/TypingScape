import Charts
import SwiftUI

/// A weekly/monthly rollup — daily activity as a bar chart plus a ranked
/// word list — separate from the shape-fill view since it's about reading
/// numbers, not the silhouette.
struct StatsView: View {
    @ObservedObject var wordStore: WordStore
    @Environment(\.dismiss) private var dismiss
    @State private var period: Period = .week
    @State private var isConfirmingReset = false

    enum Period: String, CaseIterable, Identifiable {
        case week, month
        var id: String { rawValue }
        var displayName: String { self == .week ? "이번 주" : "이번 달" }
        var days: Int { self == .week ? 7 : 30 }
    }

    private var activity: [(date: Date, count: Int)] {
        wordStore.dailyActivity(lastDays: period.days)
    }

    private var topWords: [(word: String, count: Int)] {
        wordStore.aggregatedCounts(lastDays: period.days)
            .sorted { $0.value > $1.value }
            .prefix(15)
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("통계")
                    .font(Theme.serif(17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Picker("기간", selection: $period) {
                    ForEach(Period.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .tint(Theme.ink)
                .frame(width: 150)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.inkSecondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }

            VStack(alignment: .leading, spacing: 7) {
                Theme.captionLabel("일별 입력 단어 수")
                Chart(activity, id: \.date) { point in
                    BarMark(
                        x: .value("날짜", point.date, unit: .day),
                        y: .value("단어 수", point.count)
                    )
                    .foregroundStyle(Theme.ink)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: period == .week ? 1 : 5)) { value in
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                            .font(.system(size: 9))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { AxisValueLabel().font(.system(size: 9)) }
                }
                .frame(height: 140)
            }

            VStack(alignment: .leading, spacing: 7) {
                Theme.captionLabel("자주 쓴 단어")
                if topWords.isEmpty {
                    Text("아직 기록이 없어요")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(topWords.enumerated()), id: \.element.word) { index, entry in
                            HStack(spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.inkSecondary)
                                    .frame(width: 16, alignment: .trailing)
                                Text(entry.word)
                                    .font(Theme.serif(13, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(entry.count)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("모든 기록 삭제") { isConfirmingReset = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.paperCard)
        .confirmationDialog(
            "모든 기록을 삭제할까요?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) { wordStore.resetAllData() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("오늘 기록과 지난 기록이 모두 사라지고 되돌릴 수 없어요.")
        }
    }
}
