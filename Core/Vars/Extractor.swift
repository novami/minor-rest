import Foundation

/// Vyhodnocení `extract` po úspěšné odpovědi → runtime proměnné.
nonisolated enum Extractor {
    struct Output: Sendable, Equatable {
        /// Nové hodnoty (název, hodnota) v pořadí pravidel.
        var values: [KeyValue] = []
        /// Pravidla bez výsledku nebo s chybou (`název: důvod`); původní hodnota proměnné zůstává.
        var warnings: [String] = []
    }

    /// `body` = text těla (JSON se parsuje jen při pravidle `from: body`). Vypnutá a nepojmenovaná pravidla se
    /// přeskočí.
    /// Řetězec se uloží bez uvozovek, ostatní hodnoty jako kompaktní JSON.
    static func run(_ rules: [Extract], body: String, headers: [KeyValue]) -> Output {
        var out = Output()
        var root: JSONValue?
        var rootError: String?
        for res in rules where res.enabled && !res.name.isEmpty && !res.path.isEmpty {
            if res.from == "header" {
                if let hdr = headers.first(where: { $0.name.caseInsensitiveCompare(res.path) == .orderedSame }) {
                    out.values.append(KeyValue(name: res.name, value: hdr.value))
                } else {
                    out.warnings.append("\(res.name): \(res.path)")
                }
                continue
            }
            if root == nil, rootError == nil {
                do { root = try JSONValue.parse(body) } catch { rootError = error.detail }
            }
            guard let root else {
                out.warnings.append("\(res.name): \(rootError ?? "")")
                continue
            }
            do {
                guard let val = try JSONPath(res.path).select(root).first else {
                    out.warnings.append("\(res.name): \(res.path)")
                    continue
                }
                if case .string(let str) = val {
                    out.values.append(KeyValue(name: res.name, value: str))
                } else {
                    out.values.append(KeyValue(name: res.name, value: val.compact))
                }
            } catch {
                out.warnings.append("\(res.name): \(error.detail)")
            }
        }
        return out
    }
}
