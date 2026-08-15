import AppKit
import Foundation

@MainActor
final class WordStore: ObservableObject {
    @Published private(set) var wordCounts: [String: Int] = [:] {
        didSet { persist() }
    }
    /// Completed days' word counts, keyed by "yyyy-MM-dd" — what the "지난
    /// 기록" browsing view reads from.
    @Published private(set) var history: [String: [String: Int]] = [:]
    private var trackedDay: Int
    private var trackedDate: Date
    private let defaults: UserDefaults
    private static let countsKey = "TypingScape.wordCounts"
    private static let dayKey = "TypingScape.trackedDay"
    private static let dateKey = "TypingScape.trackedDate"
    private static let historyKey = "TypingScape.wordHistory"

    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    init(now: Date = Date(), defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let today = Self.dayOrdinal(for: now)
        trackedDay = today
        trackedDate = now

        if let savedHistory = defaults.dictionary(forKey: Self.historyKey) as? [String: [String: Int]] {
            history = savedHistory
        }

        let savedDay = defaults.object(forKey: Self.dayKey) as? Int
        // Recorded before the length cap in `record(word:)` existed, a
        // pasted token/hash can already be sitting in a saved day's counts —
        // drop anything that wouldn't be accepted today.
        let savedCounts = (defaults.dictionary(forKey: Self.countsKey) as? [String: Int])?
            .filter { (2...20).contains($0.key.count) }

        if savedDay == today, let savedCounts {
            wordCounts = savedCounts
        } else if let savedDay, savedDay != today, let savedCounts, !savedCounts.isEmpty {
            // The app wasn't running at the moment the day actually rolled
            // over — without this, any day that ends while the app is
            // quit would silently vanish instead of becoming history.
            let savedDate = (defaults.object(forKey: Self.dateKey) as? Date) ?? now
            archive(savedCounts, on: savedDate)
        }
    }

    private func archive(_ counts: [String: Int], on date: Date) {
        history[Self.dateKeyFormatter.string(from: date)] = counts
        defaults.set(history, forKey: Self.historyKey)
    }

    private func persist() {
        defaults.set(wordCounts, forKey: Self.countsKey)
        defaults.set(trackedDay, forKey: Self.dayKey)
        defaults.set(trackedDate, forKey: Self.dateKey)
    }

    func record(word: String, now: Date = Date()) {
        resetIfNewDay(now: now)
        let key = word.lowercased()
        // No real word runs this long — past this it's a pasted token, hash,
        // or session ID that the spell checker doesn't reliably flag (unlike
        // short mashed-key gibberish, which `isRealWord` does catch).
        guard (2...20).contains(key.count), key.contains(where: { $0.isLetter }) else { return }
        guard Self.isRealWord(key) else { return }
        wordCounts[key, default: 0] += 1
    }

    var topWords: [(word: String, count: Int)] {
        wordCounts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    /// Past days with recorded words, most recent first.
    var historyDates: [Date] {
        history.keys.compactMap(Self.dateKeyFormatter.date(from:)).sorted(by: >)
    }

    func topWords(onDate date: Date) -> [(word: String, count: Int)] {
        let counts = history[Self.dateKeyFormatter.string(from: date)] ?? [:]
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    func wordCount(onDate date: Date) -> Int {
        history[Self.dateKeyFormatter.string(from: date)]?.count ?? 0
    }

    /// Sums word counts across the last `days` calendar days including
    /// today — what the weekly/monthly stats view ranks its word list by.
    func aggregatedCounts(lastDays days: Int, now: Date = Date()) -> [String: Int] {
        var result = wordCounts
        let calendar = Calendar.current
        for offset in 1..<max(days, 1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = Self.dateKeyFormatter.string(from: date)
            guard let counts = history[key] else { continue }
            for (word, count) in counts { result[word, default: 0] += count }
        }
        return result
    }

    /// Distinct-word count per day for the last `days` days, oldest first —
    /// what the activity chart plots.
    func dailyActivity(lastDays days: Int, now: Date = Date()) -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        return (0..<max(days, 1)).reversed().compactMap { offset -> (date: Date, count: Int)? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let count = offset == 0 ? wordCounts.count : wordCount(onDate: date)
            return (date: date, count: count)
        }
    }

    private func resetIfNewDay(now: Date) {
        let today = Self.dayOrdinal(for: now)
        guard today != trackedDay else { return }
        if !wordCounts.isEmpty { archive(wordCounts, on: trackedDate) }
        trackedDay = today
        trackedDate = now
        wordCounts.removeAll()
    }

    private static func dayOrdinal(for date: Date) -> Int {
        Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
    }

    /// Rejects mashed-key gibberish (e.g. "ㄴㄹㄴㅁㅇ") by checking the word
    /// against the system spell checker's dictionary instead of a heuristic.
    private static func isRealWord(_ word: String) -> Bool {
        let isHangul = word.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
        let language = isHangul ? "ko" : "en"
        let misspelled = NSSpellChecker.shared.checkSpelling(
            of: word, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
        )
        return misspelled.location == NSNotFound
    }
}
