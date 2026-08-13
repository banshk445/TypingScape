enum WordFlow {
    /// Interleaves words round-robin (one of each, then one more of each
    /// still-remaining word, ...) instead of repeating each word `count`
    /// times in a clump — that spreads a frequent word's repeats through
    /// the whole fill rather than letting it dominate one stretch of text.
    /// Each word's repeat count is capped so one outlier can't hijack the
    /// entire flow.
    static func build(from topWords: [(word: String, count: Int)], repeatCap: Int = 6) -> [String] {
        var pool = topWords.map { (word: $0.word, remaining: min($0.count, repeatCap)) }
        var result: [String] = []
        var addedAny = true
        while addedAny {
            addedAny = false
            for i in pool.indices where pool[i].remaining > 0 {
                result.append(pool[i].word)
                pool[i].remaining -= 1
                addedAny = true
            }
        }
        return result
    }
}
