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
}
