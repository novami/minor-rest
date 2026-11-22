import Foundation

/// Zdroj proměnné (pro UI a přehled „oko“).
public enum VarSource: String, Sendable {
    case runtime, request, folder, environment, project, global, dynamic
}

/// Sada proměnných jednoho zdroje; u složky `ref` = rel složky.
public struct VarScope: Sendable {
    public var source: VarSource
    public var ref: String
    public var vars: [Var]

    public init(_ source: VarSource, ref: String = "", vars: [Var]) {
        self.source = source
        self.ref = ref
        self.vars = vars
    }
}

/// Platná (vítězná) proměnná pro UI.
public struct VarInfo: Hashable, Sendable {
    public var name: String
    /// Hodnota tak, jak je zapsaná (u tajné prázdná).
    public var value: String
    /// Po vyhodnocení vnořených proměnných; tajné hodnoty maskované.
    public var resolved: String
    public var source: VarSource
    public var ref: String
    public var secret: Bool
}

/// Vyhodnocuje `{{proměnné}}` pro jedno odeslání (PLAN kap. 3): časové dynamické proměnné a hodnoty
/// pojmenovaných proměnných jsou v rámci resolveru pevné, přímý výskyt `{{$uuid}}` je pokaždé nový.
public final class Resolver {
    public static let masked = "***"
    static let maxDepth = 10

    private struct Entry {
        let variable: Var
        let scope: VarScope
    }

    private var vars: [String: Entry] = [:]
    private var cache: [String: (value: String, unresolved: [String])] = [:]
    private var allUnresolved: Set<String> = []
    private let now: Date

    /// Rozsahy v pořadí priority (první vyhrává): runtime → request → složky (nejbližší první)
    /// → prostředí → projekt → globální. Vypnuté a nepojmenované proměnné se ignorují.
    public init(scopes: [VarScope] = [], now: Date = Date()) {
        self.now = now
        for scope in scopes {
            for v in scope.vars where v.enabled && !v.name.isEmpty && vars[v.name] == nil {
                vars[v.name] = Entry(variable: v, scope: scope)
            }
        }
    }

    /// Nahradí proměnné; neznámé ponechá jako literál a vrátí jejich názvy. Cyklus nebo hloubka > 10 → `VAR_CYCLE`.
    public func resolve(_ s: String) throws -> (value: String, unresolved: [String]) {
        var unresolved: [String] = []
        let out = try resolve(s, stack: [], unresolved: &unresolved)
        allUnresolved.formUnion(unresolved)
        return (out, unresolved)
    }

    /// Všechny dosud nevyhodnocené proměnné (seřazené).
    public var unresolved: [String] { allUnresolved.sorted() }

    /// Platné proměnné seřazené podle názvu; tajné hodnoty se nevrací a ve výsledcích jsou maskované.
    public func explain() -> [VarInfo] {
        let secrets = vars.values.filter { $0.variable.secret && !$0.variable.value.isEmpty }.map(\.variable.value)
        return vars.map { name, e in
            var info = VarInfo(name: name, value: "", resolved: "", source: e.scope.source, ref: e.scope.ref,
                               secret: e.variable.secret)
            if !e.variable.secret {
                var ignored: [String] = []
                info.value = e.variable.value
                info.resolved = (try? resolve(e.variable.value, stack: [name], unresolved: &ignored)) ?? e.variable.value
                for s in secrets { info.resolved = info.resolved.replacingOccurrences(of: s, with: Self.masked) }
            }
            return info
        }.sorted { $0.name < $1.name }
    }

    private func resolve(_ s: String, stack: [String], unresolved: inout [String]) throws -> String {
        guard s.contains("{{") else { return s }
        var out = ""
        var rest = s[...]
        while let open = rest.range(of: "{{") {
            // `\{{` = literál `{{`
            if open.lowerBound > rest.startIndex, rest[rest.index(before: open.lowerBound)] == "\\" {
                out += rest[..<rest.index(before: open.lowerBound)] + "{{"
                rest = rest[open.upperBound...]
                continue
            }
            out += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].range(of: "}}") else {
                rest = rest[open.lowerBound...]
                break
            }
            let raw = rest[open.lowerBound..<close.upperBound]
            let name = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            rest = rest[close.upperBound...]
            if let value = try lookup(name, stack: stack, unresolved: &unresolved) {
                out += value
            } else {
                let plain = name.hasPrefix("$") ? String(name.dropFirst()) : name
                if Self.isValidName(plain) && !unresolved.contains(name) { unresolved.append(name) }
                out += raw
            }
        }
        return out + rest
    }

    private func lookup(_ name: String, stack: [String], unresolved: inout [String]) throws -> String? {
        if name.hasPrefix("$") { return dynamic(name) }
        guard Self.isValidName(name), let e = vars[name] else { return nil }
        if stack.contains(name) || stack.count >= Self.maxDepth {
            throw CoreError(.varCycle, (stack + [name]).joined(separator: " → "))
        }
        if let c = cache[name] {
            for n in c.unresolved where !unresolved.contains(n) { unresolved.append(n) }
            return c.value
        }
        var inner: [String] = []
        let value = try resolve(e.variable.value, stack: stack + [name], unresolved: &inner)
        cache[name] = (value, inner)
        for n in inner where !unresolved.contains(n) { unresolved.append(n) }
        return value
    }

    private func dynamic(_ name: String) -> String? {
        switch name {
        case "$uuid": return UUID().uuidString.lowercased()
        case "$ulid": return ULID.make()
        case "$timestamp": return String(Int64(now.timeIntervalSince1970))
        case "$timestampMs": return String(Int64(now.timeIntervalSince1970 * 1000))
        case "$isoTimestamp":
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.string(from: now)
        case "$randomInt": return String(Int.random(in: 0...1000))
        case "$randomString":
            let alnum = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
            return String((0..<16).map { _ in alnum.randomElement()! })
        default: return nil
        }
    }

    /// Název proměnné `[A-Za-z0-9_.-]+`.
    static func isValidName(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || "_.-".unicodeScalars.contains($0)
        }
    }
}
