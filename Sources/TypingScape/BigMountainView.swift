import SwiftUI
import UniformTypeIdentifiers

/// Same `MountainWordCloud` as the menu bar dropdown, just given a lot more
/// room — the placement algorithm and image mask are already resolution
/// independent, so this is the whole implementation. Adds pickers for the
/// image preset/custom photo, the word-cloud style, and the background
/// texture, so different looks can be compared side by side.
struct BigMountainView: View {
    @ObservedObject var wordStore: WordStore
    @ObservedObject var maskStore: MaskStore
    @ObservedObject var styleStore: StyleStore
    @State private var isPickingPhoto = false
    @State private var isShowingStats = false
    /// `nil` means "today, live" — anything else pins the display to a
    /// completed past day from `wordStore.history`.
    @State private var selectedHistoryDate: Date?

    private var isCustomSelected: Bool {
        if case .custom = maskStore.selection { return true }
        return false
    }

    private var presetMenuLabel: String {
        if isCustomSelected { return "사진" }
        if case .preset(let preset) = maskStore.selection { return preset.displayName }
        return "이미지"
    }

    private var displayWords: [(word: String, count: Int)] {
        guard let selectedHistoryDate else { return wordStore.topWords }
        return wordStore.topWords(onDate: selectedHistoryDate)
    }

    private var displayWordCount: Int {
        guard let selectedHistoryDate else { return wordStore.wordCounts.count }
        return wordStore.wordCount(onDate: selectedHistoryDate)
    }

    private var displayCountLabel: String {
        guard let selectedHistoryDate else { return "오늘" }
        return Self.historyButtonFormatter.string(from: selectedHistoryDate)
    }

    private static let editionDate: String = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 EEEE"
        return formatter.string(from: Date())
    }()

    private static let historyButtonFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M/d(E)"
        return formatter
    }()

    var body: some View {
        ZStack {
            ThemedBackground(style: styleStore.backgroundStyle).ignoresSafeArea()

            VStack(spacing: 16) {
                // A nameplate, not a plain centered title — the ink rules
                // above/below and the edition-date byline are what make
                // this read as a masthead instead of a generic app header.
                VStack(spacing: 6) {
                    Rectangle().fill(Theme.ink).frame(height: 1.5)
                    HStack(alignment: .firstTextBaseline) {
                        Text("TYPINGSCAPE")
                            .font(.system(size: 21, weight: .bold, design: .serif))
                            .tracking(3)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(Self.editionDate)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)
                        if !wordStore.historyDates.isEmpty {
                            Menu {
                                Button("오늘") { selectedHistoryDate = nil }
                                ForEach(wordStore.historyDates, id: \.self) { date in
                                    Button(Self.historyButtonFormatter.string(from: date)) { selectedHistoryDate = date }
                                }
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 12))
                                    .foregroundStyle(selectedHistoryDate == nil ? Theme.inkSecondary : Theme.ink)
                            }
                            .menuStyle(.button)
                            .buttonStyle(.plain)
                            .padding(.leading, 10)
                        }
                        Button {
                            isShowingStats = true
                        } label: {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 10)
                    }
                    Rectangle().fill(Theme.ink).frame(height: 1.5)
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)

                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Theme.captionLabel("모양")
                        Menu {
                            ForEach(MaskPresetGroup.allCases, id: \.self) { group in
                                Section(group.displayName) {
                                    ForEach(MaskPreset.allCases.filter { $0.group == group }) { preset in
                                        Button(preset.displayName) { maskStore.select(.preset(preset)) }
                                    }
                                }
                            }
                            Section {
                                Button("사진 선택…") { isPickingPhoto = true }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(presetMenuLabel)
                                Image(systemName: "chevron.down").font(.system(size: 9))
                            }
                        }
                        .menuStyle(.button)
                        .buttonStyle(SelectableButtonStyle(isSelected: true))
                    }

                    if maskStore.isLoading {
                        ProgressView().controlSize(.small).tint(Theme.ink).padding(.top, 22)
                    }

                    Divider().frame(height: 34).padding(.top, 20)

                    VStack(alignment: .leading, spacing: 7) {
                        Theme.captionLabel("단어 스타일")
                        Picker("단어 스타일", selection: $styleStore.wordCloudStyle) {
                            ForEach(WordCloudStyle.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 130)
                        .tint(Theme.ink)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Theme.captionLabel("배경")
                        Picker("배경", selection: $styleStore.backgroundStyle) {
                            ForEach(BackgroundStyle.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 170)
                        .tint(Theme.ink)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .themedCard()

                if maskStore.mask == nil, !maskStore.isLoading {
                    Spacer()
                    Text("이미지를 불러오지 못했어요")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSecondary)
                    Spacer()
                } else {
                    MountainWordCloud(topWords: Array(displayWords.prefix(400)), mask: maskStore.mask, style: styleStore.wordCloudStyle, swellOffset: maskStore.swellOffset)
                        .frame(minWidth: 1100, minHeight: 750)
                }

                Theme.wordCountText(displayWordCount, label: displayCountLabel)
                    .padding(.bottom, 18)
            }
        }
        .fileImporter(isPresented: $isPickingPhoto, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                maskStore.select(.custom(url))
            }
        }
        .sheet(isPresented: $isShowingStats) {
            StatsView(wordStore: wordStore)
                .preferredColorScheme(styleStore.backgroundStyle.colorScheme)
        }
        .preferredColorScheme(styleStore.backgroundStyle.colorScheme)
        .onAppear { maskStore.viewDidAppear() }
        .onDisappear { maskStore.viewDidDisappear() }
    }
}
