enum DiffToken {
    case unchanged(String)
    case removed(String)
    case added(String)
}

struct Correction {
    let removedText: String
    let addedText: String
    var isReverted: Bool = false
}

enum Segment {
    case text(String)
    case correction(Int)
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

    static func group(_ tokens: [DiffToken]) -> (segments: [Segment], corrections: [Correction]) {
        var segments: [Segment] = []
        var corrections: [Correction] = []
        var i = 0
        while i < tokens.count {
            switch tokens[i] {
            case .unchanged(let text):
                segments.append(.text(text))
                i += 1
            case .removed, .added:
                var removed = ""
                var added = ""
                loop: while i < tokens.count {
                    switch tokens[i] {
                    case .removed(let text):
                        removed += text
                        i += 1
                    case .added(let text):
                        added += text
                        i += 1
                    case .unchanged:
                        break loop
                    }
                }
                corrections.append(Correction(removedText: removed, addedText: added))
                segments.append(.correction(corrections.count - 1))
            }
        }
        return (segments, corrections)
    }

    static func finalText(segments: [Segment], corrections: [Correction]) -> String {
        var result = ""
        for segment in segments {
            switch segment {
            case .text(let text):
                result += text
            case .correction(let index):
                let correction = corrections[index]
                result += correction.isReverted ? correction.removedText : correction.addedText
            }
        }
        return result
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
