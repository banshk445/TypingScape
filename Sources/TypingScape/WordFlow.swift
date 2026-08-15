enum WordFlow {
    /// Interleaves words round-robin (one of each, then one more of each
    /// still-remaining word, ...) instead of repeating each word `count`
    /// times in a clump — that spreads a frequent word's repeats through
    /// the whole fill rather than letting it dominate one stretch of text.
    /// Each word's repeat count is capped so one outlier can't hijack the
    /// entire flow. The original count travels with each entry (not just
    /// the cycle-limited `remaining`) so the renderer can still size a
    /// word by how often it was really typed today.
    static func build(from topWords: [(word: String, count: Int)], repeatCap: Int = 3) -> [(word: String, count: Int)] {
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
