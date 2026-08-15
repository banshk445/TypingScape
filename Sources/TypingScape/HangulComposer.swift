/// Composes 2-beolsik Hangul jamo keystrokes into syllables — what a real
/// Korean input method does, needed because `TerminalKeyTracker` sees keys
/// before any OS-level composition happens (unlike `FocusedTextTracker`,
/// which reads the already-composed field value).
///
/// A 2-beolsik keyboard types each jamo directly; compound vowels/finals
/// (ㅘ, ㄳ, ...) are two base jamo combined by the composer, not separate
/// keys. The one genuinely tricky part: a trailing consonant is ambiguous
/// until the *next* keystroke — "가나" types ㄱㅏㄴㅏ, and that ㄴ has to
/// retroactively give itself back to become 나's initial consonant once
/// the following ㅏ shows up wanting it, rather than staying as 간's final.
struct HangulComposer {
    private static let choChars: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let jungChars: [Character] = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    private static let jongChars: [Character] = Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")

    private static let choIndex: [Character: Int] = Dictionary(uniqueKeysWithValues: choChars.enumerated().map { ($1, $0) })
    private static let jungIndex: [Character: Int] = Dictionary(uniqueKeysWithValues: jungChars.enumerated().map { ($1, $0) })
    // 1-based: 0 is reserved for "no final" in the Unicode composition formula.
    private static let jongIndex: [Character: Int] = Dictionary(uniqueKeysWithValues: jongChars.enumerated().map { ($1, $0 + 1) })

    private static let jungCombine: [Character: [Character: Character]] = [
        "ㅗ": ["ㅏ": "ㅘ", "ㅐ": "ㅙ", "ㅣ": "ㅚ"],
        "ㅜ": ["ㅓ": "ㅝ", "ㅔ": "ㅞ", "ㅣ": "ㅟ"],
        "ㅡ": ["ㅣ": "ㅢ"],
    ]
    private static let jongCombine: [Character: [Character: Character]] = [
        "ㄱ": ["ㅅ": "ㄳ"],
        "ㄴ": ["ㅈ": "ㄵ", "ㅎ": "ㄶ"],
        "ㄹ": ["ㄱ": "ㄺ", "ㅁ": "ㄻ", "ㅂ": "ㄼ", "ㅅ": "ㄽ", "ㅌ": "ㄾ", "ㅍ": "ㄿ", "ㅎ": "ㅀ"],
        "ㅂ": ["ㅅ": "ㅄ"],
    ]
    /// Splitting a compound final when a vowel shows up wanting part of it
    /// as the next syllable's initial — e.g. ㄺ (ㄹ+ㄱ) keeps ㄹ as this
    /// syllable's final and gives ㄱ to the next one.
    private static let jongSplit: [Character: (keep: Character, move: Character)] = [
        "ㄳ": ("ㄱ", "ㅅ"), "ㄵ": ("ㄴ", "ㅈ"), "ㄶ": ("ㄴ", "ㅎ"),
        "ㄺ": ("ㄹ", "ㄱ"), "ㄻ": ("ㄹ", "ㅁ"), "ㄼ": ("ㄹ", "ㅂ"),
        "ㄽ": ("ㄹ", "ㅅ"), "ㄾ": ("ㄹ", "ㅌ"), "ㄿ": ("ㄹ", "ㅍ"),
        "ㅀ": ("ㄹ", "ㅎ"), "ㅄ": ("ㅂ", "ㅅ"),
    ]

    static func isJamo(_ ch: Character) -> Bool {
        choIndex[ch] != nil || jungIndex[ch] != nil
    }

    private var cho: Character?
    private var jung: Character?
    private var jong: Character?
    private enum Step { case setCho, setJung, setJong, combineJung(prev: Character), combineJong(prev: Character) }
    private var steps: [Step] = []

    var hasPending: Bool { cho != nil }

    /// Feed one jamo character. Returns any syllable(s) that got displaced
    /// as a side effect — empty if this keystroke only extended the
    /// syllable still in progress.
    mutating func ingest(_ ch: Character) -> String {
        if Self.choIndex[ch] != nil {
            return ingestConsonant(ch)
        } else if Self.jungIndex[ch] != nil {
            return ingestVowel(ch)
        }
        return ""
    }

    private mutating func ingestConsonant(_ ch: Character) -> String {
        guard cho != nil else {
            cho = ch
            steps.append(.setCho)
            return ""
        }
        guard jung != nil else {
            // No vowel ever arrived for the pending consonant — it can
            // never become a syllable on its own; finalize it bare.
            let out = composeOrBare()
            reset()
            cho = ch
            steps.append(.setCho)
            return out
        }
        guard let existingJong = jong else {
            // Provisional — might still get handed to the *next* syllable
            // if a vowel follows (see ingestVowel's jong-set branch).
            jong = ch
            steps.append(.setJong)
            return ""
        }
        if let combined = Self.jongCombine[existingJong]?[ch] {
            jong = combined
            steps.append(.combineJong(prev: existingJong))
            return ""
        }
        let out = composeOrBare()
        reset()
        cho = ch
        steps.append(.setCho)
        return out
    }

    private mutating func ingestVowel(_ ch: Character) -> String {
        guard cho != nil else {
            // A vowel with nothing to attach to never composes — pass it
            // through as itself (after finalizing anything pending, which
            // shouldn't be possible here since jung/jong both require cho).
            let out = composeOrBare()
            reset()
            return out + String(ch)
        }
        guard jung != nil else {
            jung = ch
            steps.append(.setJung)
            return ""
        }
        guard let existingJong = jong else {
            if let existingJung = jung, let combined = Self.jungCombine[existingJung]?[ch] {
                jung = combined
                steps.append(.combineJung(prev: existingJung))
                return ""
            }
            // No vowel-to-vowel continuation in Hangul — starts fresh,
            // and a bare vowel with no consonant finalizes immediately.
            let out = composeOrBare()
            reset()
            return out + String(ch)
        }
        // The classic re-parse: give the trailing consonant back to
        // become the next syllable's initial, now that a vowel wants it.
        if let split = Self.jongSplit[existingJong] {
            jong = split.keep
            let out = composeOrBare()
            reset()
            cho = split.move
            jung = ch
            steps = [.setCho, .setJung]
            return out
        } else {
            jong = nil
            let out = composeOrBare()
            reset()
            cho = existingJong
            jung = ch
            steps = [.setCho, .setJung]
            return out
        }
    }

    /// Undoes exactly the last jamo step (Delete/Backspace).
    mutating func backspace() {
        guard let last = steps.popLast() else { return }
        switch last {
        case .setCho: cho = nil
        case .setJung: jung = nil
        case .setJong: jong = nil
        case .combineJung(let prev): jung = prev
        case .combineJong(let prev): jong = prev
        }
    }

    /// Whatever's pending, as final — call at a word boundary (space,
    /// punctuation, Enter, losing terminal focus), since no further jamo
    /// will ever arrive to complete or redirect it.
    mutating func flush() -> String {
        let out = composeOrBare()
        reset()
        return out
    }

    private mutating func reset() {
        cho = nil; jung = nil; jong = nil; steps = []
    }

    private func composeOrBare() -> String {
        guard let cho else { return "" }
        guard let jung, let choI = Self.choIndex[cho], let jungI = Self.jungIndex[jung] else {
            return String(cho)
        }
        let jongI = jong.flatMap { Self.jongIndex[$0] } ?? 0
        let scalarValue = 0xAC00 + (choI * 21 + jungI) * 28 + jongI
        guard let scalar = Unicode.Scalar(scalarValue) else { return String(cho) }
        return String(Character(scalar))
    }
}
