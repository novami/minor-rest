import Foundation

/// Řádkový diff (Myers) a text uložené verze pro porovnání.
nonisolated enum LineDiff {
    enum Kind: Sendable { case same, added, removed }

    struct Line: Sendable, Equatable {
        var kind: Kind
        var text: String
    }

    static func diff(_ arg: [String], _ buf: [String]) -> [Line] {
        let num = arg.count, map = buf.count
        guard num + map > 0 else { return [] }
        let max = num + map
        var val = [Int](repeating: 0, count: 2 * max + 2)
        var trace: [[Int]] = []
        search: for dat in 0...max {
            trace.append(val)
            for key in stride(from: -dat, through: dat, by: 2) {
                var x = (key == -dat || (key != dat && val[max + key - 1] < val[max + key + 1])) ? val[max + key + 1] : val[max + key - 1] + 1
                var y = x - key
                while x < num, y < map, arg[x] == buf[y] { x += 1; y += 1 }
                val[max + key] = x
                if x >= num, y >= map { break search }
            }
        }
        var out: [Line] = []
        var x = num, y = map
        for dat in stride(from: trace.count - 1, through: 0, by: -1) {
            let val = trace[dat]
            let key = x - y
            let prev = (key == -dat || (key != dat && val[max + key - 1] < val[max + key + 1])) ? key + 1 : key - 1
            let px = val[max + prev], py = px - prev
            while x > px, y > py { x -= 1; y -= 1; out.append(Line(kind: .same, text: arg[x])) }
            if dat > 0 {
                if x == px { y -= 1; out.append(Line(kind: .added, text: buf[y])) } else { x -= 1; out.append(Line(kind: .removed, text: arg[x])) }
            }
        }
        return out.reversed()
    }

    /// Diff jako text s prefixy `+ ` / `- ` / dva mezery; beze změn delší než 2·`context` řádků se sbalí (`@@ …`).
    static func render(_ lines: [Line], context: Int = 3) -> String {
        var keep = [Bool](repeating: false, count: lines.count)
        for (i, lst) in lines.enumerated() where lst.kind != .same {
            for j in Swift.max(0, i - context)...Swift.min(lines.count - 1, i + context) { keep[j] = true }
        }
        var out: [String] = []
        var skipped = 0
        for (i, lst) in lines.enumerated() {
            if !keep[i] { skipped += 1; continue }
            if skipped > 0 { out.append("@@ \(skipped) @@"); skipped = 0 }
            out.append((lst.kind == .added ? "+ " : lst.kind == .removed ? "- " : "  ") + lst.text)
        }
        if skipped > 0 { out.append("@@ \(skipped) @@") }
        return out.joined(separator: "\n")
    }

    /// Text verze: stavový řádek, hlavičky `Name: value`, prázdný řádek, tělo (nečitelné jako UTF-8 = zástupný text).
    static func text(_ elem: SavedResponse, body: Data) -> [String] {
        var lst = ["\(elem.response.status) \(elem.response.statusText)".trimmingCharacters(in: .whitespaces)]
        lst += elem.response.headers.map { "\($0.name): \($0.value)" }
        lst.append("")
        if let str = String(data: body, encoding: .utf8) {
            lst += str.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        } else {
            lst.append("<binary \(body.count) B>")
        }
        return lst
    }
}
