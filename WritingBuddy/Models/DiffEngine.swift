import Foundation

enum DiffOp { case equal, add, delete }

struct DiffPart: Identifiable, Hashable {
    let id = UUID()
    let op: DiffOp
    let text: String
}

enum DiffEngine {
    /// Word-level diff using LCS, matching the JS prototype's `diffWords` behavior.
    /// Splits on runs of whitespace (preserving them as their own tokens), then
    /// produces a sequence of equal/add/delete segments.
    static func diff(original: String, current: String) -> [DiffPart] {
        let a = tokenize(original)
        let b = tokenize(current)
        let m = a.count, n = b.count

        // Build LCS DP table
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        if m > 0 && n > 0 {
            for i in stride(from: m - 1, through: 0, by: -1) {
                for j in stride(from: n - 1, through: 0, by: -1) {
                    if a[i] == b[j] {
                        dp[i][j] = dp[i + 1][j + 1] + 1
                    } else {
                        dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                    }
                }
            }
        }

        var out: [DiffPart] = []
        var i = 0, j = 0
        while i < m && j < n {
            if a[i] == b[j] {
                out.append(DiffPart(op: .equal, text: a[i]))
                i += 1; j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                out.append(DiffPart(op: .delete, text: a[i]))
                i += 1
            } else {
                out.append(DiffPart(op: .add, text: b[j]))
                j += 1
            }
        }
        while i < m { out.append(DiffPart(op: .delete, text: a[i])); i += 1 }
        while j < n { out.append(DiffPart(op: .add, text: b[j])); j += 1 }
        return out
    }

    private static func tokenize(_ s: String) -> [String] {
        // Mirror JavaScript's split(/(\s+)/): keeps whitespace runs as their
        // own tokens. This preserves spacing in the rendered diff.
        var tokens: [String] = []
        var current = ""
        var inWS: Bool? = nil
        for ch in s {
            let isWS = ch.isWhitespace
            if let wasWS = inWS, wasWS != isWS {
                tokens.append(current)
                current = ""
            }
            current.append(ch)
            inWS = isWS
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
