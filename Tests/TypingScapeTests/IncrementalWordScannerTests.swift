import XCTest
@testable import TypingScape

final class IncrementalWordScannerTests: XCTestCase {
    func testEmitsWordOnDelimiter() {
        var scanner = IncrementalWordScanner()
        var words: [String] = []
        scanner.ingest("안녕 ") { words.append($0) }
        XCTAssertEqual(words, ["안녕"])
    }

    func testLeavesInProgressWordUncommitted() {
        var scanner = IncrementalWordScanner()
        var words: [String] = []
        scanner.ingest("hel") { words.append($0) }
        XCTAssertEqual(words, [])
        scanner.ingest("hello ") { words.append($0) }
        XCTAssertEqual(words, ["hello"])
    }

    func testDoesNotReemitAlreadyProcessedWords() {
        var scanner = IncrementalWordScanner()
        var words: [String] = []
        scanner.ingest("foo bar ") { words.append($0) }
        scanner.ingest("foo bar baz ") { words.append($0) }
        XCTAssertEqual(words, ["foo", "bar", "baz"])
    }

    func testFlushConfirmsAnInProgressTrailingWord() {
        var scanner = IncrementalWordScanner()
        var words: [String] = []
        scanner.ingest("hel") { words.append($0) }
        XCTAssertEqual(words, [])
        scanner.flush("hel") { words.append($0) }
        XCTAssertEqual(words, ["hel"])
    }

    func testFlushIsANoOpWhenNothingIsPending() {
        var scanner = IncrementalWordScanner()
        var words: [String] = []
        scanner.ingest("hello ") { words.append($0) }
        scanner.flush("hello ") { words.append($0) }
        XCTAssertEqual(words, ["hello"])
    }

    func testResyncsWithoutCrashingWhenTextIsNotAContinuation() {
        var scanner = IncrementalWordScanner(processedText: "hello world")
        var words: [String] = []
        scanner.ingest("totally different text") { words.append($0) }
        XCTAssertEqual(words, [])
        XCTAssertEqual(scanner.processedText, "totally different text")
    }
}
