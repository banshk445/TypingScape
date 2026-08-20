import XCTest
@testable import TypingScape

@MainActor
final class WordStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "WordStoreTests.\(UUID().uuidString)")!
    }

    func testRecordCountsAndLowercases() {
        let store = WordStore(defaults: freshDefaults())
        store.record(word: "Swift")
        store.record(word: "swift")
        store.record(word: "swift")
        XCTAssertEqual(store.wordCounts["swift"], 3)
        XCTAssertEqual(store.topWords.first?.word, "swift")
    }

    func testIgnoresSingleCharAndNonLetterTokens() {
        let store = WordStore(defaults: freshDefaults())
        store.record(word: "1")
        store.record(word: "42")
        store.record(word: "ok")
        XCTAssertNil(store.wordCounts["1"])
        XCTAssertNil(store.wordCounts["42"])
        XCTAssertEqual(store.wordCounts["ok"], 1)
    }

    func testRejectsGibberish() {
        let store = WordStore(defaults: freshDefaults())
        store.record(word: "ㄴㄹㄴㅁㅇㅁㄴㅁㄹ")
        store.record(word: "qwzxkyjpv")
        store.record(word: "안녕하세요")
        XCTAssertTrue(store.wordCounts.isEmpty || store.wordCounts.keys.allSatisfy { $0 == "안녕하세요" })
        XCTAssertEqual(store.wordCounts["안녕하세요"], 1)
    }

    func testResetsOnNewDay() {
        let store = WordStore(now: Date(timeIntervalSince1970: 0), defaults: freshDefaults())
        store.record(word: "hello", now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(store.wordCounts["hello"], 1)

        store.record(word: "world", now: Date(timeIntervalSince1970: 0) + 86_400)
        XCTAssertNil(store.wordCounts["hello"])
        XCTAssertEqual(store.wordCounts["world"], 1)
    }

    func testRestoresTodaysCountsAfterRelaunch() {
        let defaults = freshDefaults()
        let now = Date(timeIntervalSince1970: 0)
        let first = WordStore(now: now, defaults: defaults)
        first.record(word: "hello", now: now)
        first.record(word: "hello", now: now)

        let relaunched = WordStore(now: now, defaults: defaults)
        XCTAssertEqual(relaunched.wordCounts["hello"], 2)
    }

    func testDoesNotRestoreStaleDayCounts() {
        let defaults = freshDefaults()
        let yesterday = Date(timeIntervalSince1970: 0)
        let first = WordStore(now: yesterday, defaults: defaults)
        first.record(word: "hello", now: yesterday)

        let today = yesterday + 86_400
        let relaunched = WordStore(now: today, defaults: defaults)
        XCTAssertNil(relaunched.wordCounts["hello"])
    }

    func testArchivesPreviousDayWhenDayRollsOverWhileRunning() {
        let store = WordStore(now: Date(timeIntervalSince1970: 0), defaults: freshDefaults())
        let day1 = Date(timeIntervalSince1970: 0)
        store.record(word: "hello", now: day1)
        store.record(word: "hello", now: day1)

        let day2 = day1 + 86_400
        store.record(word: "world", now: day2)

        XCTAssertEqual(store.topWords(onDate: day1).first?.word, "hello")
        XCTAssertEqual(store.wordCount(onDate: day1), 1)
        XCTAssertEqual(store.wordCounts["world"], 1)
    }

    func testArchivesYesterdayIntoHistoryWhenAppWasClosedAtRollover() {
        // Nothing was recorded exactly at the moment the day rolled over —
        // the app was simply closed and reopened the next day — but the
        // previous session's counts are still sitting in UserDefaults and
        // must not be silently lost.
        let defaults = freshDefaults()
        let yesterday = Date(timeIntervalSince1970: 0)
        let first = WordStore(now: yesterday, defaults: defaults)
        first.record(word: "hello", now: yesterday)
        first.record(word: "hello", now: yesterday)

        let today = yesterday + 86_400
        let relaunched = WordStore(now: today, defaults: defaults)
        XCTAssertEqual(relaunched.topWords(onDate: yesterday).first?.word, "hello")
        XCTAssertEqual(relaunched.wordCount(onDate: yesterday), 1)
    }

    func testAggregatedCountsSumsAcrossTheWindowIncludingToday() {
        let day0 = Date(timeIntervalSince1970: 0)
        let store = WordStore(now: day0, defaults: freshDefaults())
        store.record(word: "hello", now: day0)

        let day1 = day0 + 86_400
        store.record(word: "hello", now: day1)
        store.record(word: "world", now: day1)

        let day2 = day1 + 86_400
        store.record(word: "hello", now: day2) // still today, live in wordCounts

        let totals = store.aggregatedCounts(lastDays: 7, now: day2)
        XCTAssertEqual(totals["hello"], 3)
        XCTAssertEqual(totals["world"], 1)
    }

    func testAggregatedCountsExcludesDaysOutsideTheWindow() {
        let day0 = Date(timeIntervalSince1970: 0)
        let store = WordStore(now: day0, defaults: freshDefaults())
        store.record(word: "old", now: day0)

        let day1 = day0 + 86_400
        store.record(word: "recent", now: day1)

        let totals = store.aggregatedCounts(lastDays: 1, now: day1) // just "today" (day1)
        XCTAssertNil(totals["old"])
        XCTAssertEqual(totals["recent"], 1)
    }

    func testDailyActivityReturnsOneEntryPerDayOldestFirst() {
        let day0 = Date(timeIntervalSince1970: 0)
        let store = WordStore(now: day0, defaults: freshDefaults())
        store.record(word: "cat", now: day0)
        store.record(word: "dog", now: day0)

        let day1 = day0 + 86_400
        store.record(word: "sun", now: day1)

        let activity = store.dailyActivity(lastDays: 2, now: day1)
        XCTAssertEqual(activity.count, 2)
        XCTAssertEqual(activity[0].count, 2) // day0: cat, dog
        XCTAssertEqual(activity[1].count, 1) // day1 (today): sun
    }

    func testHistoryOlderThanRetentionWindowIsDroppedOnArchive() {
        let day0 = Date(timeIntervalSince1970: 0)
        let store = WordStore(now: day0, defaults: freshDefaults())
        store.record(word: "old", now: day0)

        // Well past the window — archiving this day prunes day0.
        let muchLater = day0 + 86_400 * Double(WordStore.historyRetentionDays + 5)
        store.record(word: "recent", now: muchLater)

        XCTAssertEqual(store.wordCount(onDate: day0), 0)
        XCTAssertEqual(store.wordCounts["recent"], 1)
    }

    func testHistoryWithinRetentionWindowIsKept() {
        let day0 = Date(timeIntervalSince1970: 0)
        let store = WordStore(now: day0, defaults: freshDefaults())
        store.record(word: "old", now: day0)

        let nextDay = day0 + 86_400
        store.record(word: "recent", now: nextDay)

        XCTAssertEqual(store.topWords(onDate: day0).first?.word, "old")
    }

    func testStaleHistoryIsPrunedOnLaunch() {
        let defaults = freshDefaults()
        let day0 = Date(timeIntervalSince1970: 0)
        let first = WordStore(now: day0, defaults: defaults)
        first.record(word: "old", now: day0)
        first.record(word: "next", now: day0 + 86_400) // archives day0

        // Relaunching much later should drop it without needing an archive.
        let muchLater = day0 + 86_400 * Double(WordStore.historyRetentionDays + 5)
        let relaunched = WordStore(now: muchLater, defaults: defaults)
        XCTAssertEqual(relaunched.wordCount(onDate: day0), 0)
        XCTAssertTrue(relaunched.historyDates.isEmpty)
    }

    func testBestDailyWordTotalCountsRepeats() {
        // Shapes are filled by placed words, and a word typed 3 times is
        // placed 3 times — so the total has to count repeats, not distinct
        // words, or the gate would sit far above what filling really takes.
        let day0 = Date(timeIntervalSince1970: 0)
        let store = WordStore(now: day0, defaults: freshDefaults())
        store.record(word: "hello", now: day0)
        store.record(word: "hello", now: day0)
        store.record(word: "hello", now: day0)
        XCTAssertEqual(store.wordCounts.count, 1)
        XCTAssertEqual(store.bestDailyWordTotal, 3)
    }

    func testBestDailyWordTotalSurvivesTheDayRollingOver() {
        let day0 = Date(timeIntervalSince1970: 0)
        let store = WordStore(now: day0, defaults: freshDefaults())
        store.record(word: "hello", now: day0)
        store.record(word: "world", now: day0)
        XCTAssertEqual(store.bestDailyWordTotal, 2)

        // A quiet next day must not take the record away — unlocks key off
        // this, and a shape filled once shouldn't lock again overnight.
        let day1 = day0 + 86_400
        store.record(word: "solo", now: day1)
        XCTAssertEqual(store.wordCounts.count, 1)
        XCTAssertEqual(store.bestDailyWordTotal, 2)
    }

    func testResetAllDataClearsBestDailyWordTotal() {
        let day0 = Date(timeIntervalSince1970: 0)
        let store = WordStore(now: day0, defaults: freshDefaults())
        store.record(word: "hello", now: day0)
        store.record(word: "world", now: day0 + 86_400)
        XCTAssertGreaterThan(store.bestDailyWordTotal, 0)

        store.resetAllData()
        XCTAssertEqual(store.bestDailyWordTotal, 0)
    }

    func testResetAllDataClearsLiveCountsAndHistory() {
        let day0 = Date(timeIntervalSince1970: 0)
        let store = WordStore(now: day0, defaults: freshDefaults())
        store.record(word: "hello", now: day0)

        let day1 = day0 + 86_400
        store.record(word: "world", now: day1) // archives day0 into history

        store.resetAllData()
        XCTAssertTrue(store.wordCounts.isEmpty)
        XCTAssertTrue(store.historyDates.isEmpty)
        XCTAssertEqual(store.wordCount(onDate: day0), 0)
    }
}
