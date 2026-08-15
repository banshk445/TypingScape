enum WordFlow {
    /// Interleaves words round-robin (one of each, then one more of each
    /// still-remaining word, ...) instead of repeating each word `count`
    /// times in a clump — that spreads a frequent word's repeats through
    /// the whole fill rather than letting it dominate one stretch of text.
    /// No artificial cap by default: a word repeats exactly as many times
    /// as it was actually typed, not padded further — the renderer stops
    /// once this list runs out instead of cycling back through it, so the
    /// shape only fills as much as real typing data supports. `repeatCap`
    /// still exists for callers that want a ceiling anyway.
    static func build(from topWords: [(word: String, count: Int)], repeatCap: Int = .max) -> [(word: String, count: Int)] {
        var pool = topWords.map { (word: $0.word, count: $0.count, remaining: min($0.count, repeatCap)) }
        var result: [(word: String, count: Int)] = []
        var addedAny = true
        while addedAny {
            addedAny = false
            for i in pool.indices where pool[i].remaining > 0 {
                result.append((word: pool[i].word, count: pool[i].count))
                pool[i].remaining -= 1
                addedAny = true
            }
        }
        return result
    }
}
