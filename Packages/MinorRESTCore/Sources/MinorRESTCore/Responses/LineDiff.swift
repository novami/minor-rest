import Foundation

/// Řádkový diff (Myers) a text uložené verze pro porovnání.
public enum LineDiff {
    public enum Kind: Sendable { case same, added, removed }

    public struct Line: Sendable, Equatable {
        public var kind: Kind
        public var text: String
    }

    public static func diff(_ a: [String], _ b: [String]) -> [Line] {
        let n = a.count, m = b.count
        guard n + m > 0 else { return [] }
        let max = n + m
        var v = [Int](repeating: 0, count: 2 * max + 2)
        var trace: [[Int]] = []
        search: for d in 0...max {
            trace.append(v)
            for k in stride(from: -d, through: d, by: 2) {
                var x = (k == -d || (k != d && v[max + k - 1] < v[max + k + 1])) ? v[max + k + 1] : v[max + k - 1] + 1
                var y = x - k
                while x < n, y < m, a[x] == b[y] { x += 1; y += 1 }
                v[max + k] = x
                if x >= n, y >= m { break search }
            }
        }
        var out: [Line] = []
        var x = n, y = m
        for d in stride(from: trace.count - 1, through: 0, by: -1) {
            let v = trace[d]
            let k = x - y
            let prev = (k == -d || (k != d && v[max + k - 1] < v[max + k + 1])) ? k + 1 : k - 1
            let px = v[max + prev], py = px - prev
            while x > px, y > py { x -= 1; y -= 1; out.append(Line(kind: .same, text: a[x])) }
            if d > 0 {
                if x == px { y -= 1; out.append(Line(kind: .added, text: b[y])) }
                else { x -= 1; out.append(Line(kind: .removed, text: a[x])) }
            }
        }
        return out.reversed()
    }

    /// Diff jako text s prefixy `+ ` / `- ` / dva mezery; beze změn delší než 2·`context` řádků se sbalí (`@@ …`).
    public static func render(_ lines: [Line], context: Int = 3) -> String {
        var keep = [Bool](repeating: false, count: lines.count)
        for (i, l) in lines.enumerated() where l.kind != .same {
            for j in Swift.max(0, i - context)...Swift.min(lines.count - 1, i + context) { keep[j] = true }
        }
        var out: [String] = []
        var skipped = 0
        for (i, l) in lines.enumerated() {
            if !keep[i] { skipped += 1; continue }
            if skipped > 0 { out.append("@@ \(skipped) @@"); skipped = 0 }
            out.append((l.kind == .added ? "+ " : l.kind == .removed ? "- " : "  ") + l.text)
        }
        if skipped > 0 { out.append("@@ \(skipped) @@") }
        return out.joined(separator: "\n")
    }

    /// Text verze: stavový řádek, hlavičky `Name: value`, prázdný řádek, tělo (nečitelné jako UTF-8 = zástupný text).
    public static func text(_ e: SavedResponse, body: Data) -> [String] {
        var l = ["\(e.response.status) \(e.response.statusText)".trimmingCharacters(in: .whitespaces)]
        l += e.response.headers.map { "\($0.name): \($0.value)" }
        l.append("")
        if let s = String(data: body, encoding: .utf8) {
            l += s.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        } else {
            l.append("<binary \(body.count) B>")
        }
        return l
    }
}
