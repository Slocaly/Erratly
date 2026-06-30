enum DiffToken {
    case unchanged(String)
    case removed(String)
    case added(String)
}

enum Diff {
    static func compute(original: String, corrected: String) -> [DiffToken] {
        let a = tokenize(original)
        let b = tokenize(corrected)

        if a.isEmpty { return b.map { .added($0) } }
        if b.isEmpty { return a.map { .removed($0) } }

        let m = a.count, n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = a[i-1] == b[j-1]
                    ? dp[i-1][j-1] + 1
                    : max(dp[i-1][j], dp[i][j-1])
            }
        }

        var result: [DiffToken] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && a[i-1] == b[j-1] {
                result.append(.unchanged(a[i-1]))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
                result.append(.added(b[j-1]))
                j -= 1
            } else {
                result.append(.removed(a[i-1]))
                i -= 1
            }
        }

        return result.reversed()
    }

    // Splits into alternating runs of word characters and non-word characters
    // e.g. "hello, world!" → ["hello", ", ", "world", "!"]
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inWord: Bool? = nil

        for char in text {
            let isWord = char.isLetter || char.isNumber
            if let w = inWord, isWord == w {
                current.append(char)
            } else {
                if !current.isEmpty { tokens.append(current) }
                current = String(char)
                inWord = isWord
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
