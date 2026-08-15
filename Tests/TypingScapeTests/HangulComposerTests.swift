import XCTest
@testable import TypingScape

final class HangulComposerTests: XCTestCase {
    private func compose(_ jamo: String) -> String {
        var composer = HangulComposer()
        var out = ""
        for ch in jamo { out += composer.ingest(ch) }
        out += composer.flush()
        return out
    }

    func testSimpleSyllablesWithNoFinal() {
        // ㄱㅏㄴㅏㄷㅏ — each consonant only ever sees a vowel next, never
        // another consonant, so there's no final-consonant ambiguity here.
        XCTAssertEqual(compose("ㄱㅏㄴㅏㄷㅏ"), "가나다")
    }

    func testFinalConsonantThatStaysPut() {
        // ㅇㅏㄴ + ㄴㅕㅇ — the first ㄴ is followed by another consonant
        // (not a vowel), so it correctly stays as 안's final.
        XCTAssertEqual(compose("ㅇㅏㄴㄴㅕㅇ"), "안녕")
    }

    func testTrailingConsonantHandedToNextSyllable() {
        // ㅎㅏㄴㅏ — the ㄴ is provisionally 하's final, but the following
        // ㅏ wants it as 나's initial instead. This is the exact pattern
        // that broke before HangulComposer existed (recorded as raw ㅎㅏㄴㅏ).
        XCTAssertEqual(compose("ㅎㅏㄴㅏ"), "하나")
    }

    func testCompoundVowel() {
        // ㅎㅗㅏ — ㅗ then ㅏ combine into ㅘ before ㅎ ever gets a final.
        XCTAssertEqual(compose("ㅎㅗㅏ"), "화")
    }

    func testCompoundFinalConsonant() {
        // ㄷㅏㄹㄱ — ㄹ then ㄱ combine into the compound final ㄺ (닭).
        XCTAssertEqual(compose("ㄷㅏㄹㄱ"), "닭")
    }

    func testCompoundFinalSplitsWhenVowelFollows() {
        // 닭 + ㅣ — ㄺ splits: ㄹ stays as 달's final, ㄱ moves to become 기's initial.
        XCTAssertEqual(compose("ㄷㅏㄹㄱㅣ"), "달기")
    }

    func testBareConsonantWithNoFollowingVowel() {
        // A lone consonant with nothing after it can't compose — passes
        // through as itself, same as a real IME.
        XCTAssertEqual(compose("ㄱ"), "ㄱ")
    }

    func testBareVowelWithNoPrecedingConsonant() {
        XCTAssertEqual(compose("ㅏ"), "ㅏ")
    }

    func testBackspaceDecomposesBeforeErasing() {
        var composer = HangulComposer()
        var out = ""
        for ch in "ㅎㅏㄴ" { out += composer.ingest(ch) } // 한 pending (jong=ㄴ)
        XCTAssertEqual(out, "")
        composer.backspace() // undo the jong -> 하 pending
        out += composer.flush()
        XCTAssertEqual(out, "하")
    }
}
