import Foundation

/// Vyhodnocení `extract` po úspěšné odpovědi → runtime proměnné.
public enum Extractor {
    public struct Output: Sendable, Equatable {
        /// Nové hodnoty (název, hodnota) v pořadí pravidel.
        public var values: [KV] = []
        /// Pravidla bez výsledku nebo s chybou (`název: důvod`); původní hodnota proměnné zůstává.
        public var warnings: [String] = []
    }

    /// `body` = text těla (JSON se parsuje jen při pravidle `from: body`). Vypnutá a nepojmenovaná pravidla se přeskočí.
    /// Řetězec se uloží bez uvozovek, ostatní hodnoty jako kompaktní JSON.
    public static func run(_ rules: [Extract], body: String, headers: [KV]) -> Output {
        var out = Output()
        var root: JSONValue?
        var rootError: String?
        for r in rules where r.enabled && !r.name.isEmpty && !r.path.isEmpty {
            if r.from == "header" {
                if let h = headers.first(where: { $0.name.caseInsensitiveCompare(r.path) == .orderedSame }) {
                    out.values.append(KV(name: r.name, value: h.value))
                } else {
                    out.warnings.append("\(r.name): \(r.path)")
                }
                continue
            }
            if root == nil, rootError == nil {
                do { root = try JSONValue.parse(body) } catch { rootError = error.detail }
            }
            guard let root else { out.warnings.append("\(r.name): \(rootError ?? "")"); continue }
            do {
                guard let v = try JSONPath(r.path).select(root).first else {
                    out.warnings.append("\(r.name): \(r.path)")
                    continue
                }
                if case .string(let s) = v { out.values.append(KV(name: r.name, value: s)) }
                else { out.values.append(KV(name: r.name, value: v.compact)) }
            } catch {
                out.warnings.append("\(r.name): \(error.detail)")
            }
        }
        return out
    }
}
