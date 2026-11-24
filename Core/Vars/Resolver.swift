import Foundation

/// Zdroj proměnné (pro UI a přehled „oko“).
nonisolated enum VarSource: String, Sendable {
    case runtime, request, folder, environment, project, global, dynamic
}

/// Sada proměnných jednoho zdroje; u složky `ref` = rel složky.
nonisolated struct VarScope: Sendable {
    var source: VarSource
    var ref: String
    var vars: [Var]

    init(_ source: VarSource, ref: String = "", vars: [Var]) {
        self.source = source
        self.ref = ref
        self.vars = vars
    }
}

/// Platná (vítězná) proměnná pro UI.
nonisolated struct VarInfo: Hashable, Sendable {
    var name: String
    /// Hodnota tak, jak je zapsaná (u tajné prázdná).
    var value: String
    /// Po vyhodnocení vnořených proměnných; tajné hodnoty maskované.
    var resolved: String
    var source: VarSource
    var ref: String
    var secret: Bool
}

/// Vyhodnocuje `{{proměnné}}` pro jedno odeslání (PLAN kap. 3): časové dynamické proměnné a hodnoty
/// pojmenovaných proměnných jsou v rámci resolveru pevné, přímý výskyt `{{$uuid}}` je pokaždé nový.
nonisolated final class Resolver {
    static let masked = "***"
    /// Dynamické proměnné (`{{$uuid}}` …) pro našeptávač a zvýraznění.
    static let dynamicNames = [
        "$uuid", "$ulid", "$timestamp", "$timestampMs", "$isoTimestamp",
        "$randomInt", "$randomString"
    ]
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
    init(scopes: [VarScope] = [], now: Date = Date()) {
        self.now = now
        for scope in scopes {
            for val in scope.vars where val.enabled && !val.name.isEmpty && vars[val.name] == nil {
                vars[val.name] = Entry(variable: val, scope: scope)
            }
        }
    }

    /// Nahradí proměnné; neznámé ponechá jako literál a vrátí jejich názvy. Cyklus nebo hloubka > 10 → `VAR_CYCLE`.
    func resolve(_ str: String) throws -> (value: String, unresolved: [String]) {
        var unresolved: [String] = []
        let out = try resolve(str, stack: [], unresolved: &unresolved)
        allUnresolved.formUnion(unresolved)
        return (out, unresolved)
    }

    /// Všechny dosud nevyhodnocené proměnné (seřazené).
    var unresolved: [String] { allUnresolved.sorted() }

    /// Platné proměnné seřazené podle názvu; tajné hodnoty se nevrací a ve výsledcích jsou maskované.
    func explain() -> [VarInfo] {
        let secrets = vars.values.filter { $0.variable.secret && !$0.variable.value.isEmpty }.map(\.variable.value)
        return vars.map { name, elem in
            var info = VarInfo(
                name: name, value: "", resolved: "", source: elem.scope.source, ref: elem.scope.ref,
                secret: elem.variable.secret)
            if !elem.variable.secret {
                var ignored: [String] = []
                info.value = elem.variable.value
                info.resolved =
                    (try? resolve(elem.variable.value, stack: [name], unresolved: &ignored)) ?? elem.variable.value
                for str in secrets { info.resolved = info.resolved.replacingOccurrences(of: str, with: Self.masked) }
            }
            return info
        }.sorted { $0.name < $1.name }
    }

    private func resolve(_ str: String, stack: [String], unresolved: inout [String]) throws -> String {
        guard str.contains("{{") else { return str }
        var out = ""
        var rest = str[...]
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
        guard Self.isValidName(name), let elem = vars[name] else { return nil }
        if stack.contains(name) || stack.count >= Self.maxDepth {
            throw CoreError(.varCycle, (stack + [name]).joined(separator: " → "))
        }
        if let cur = cache[name] {
            for num in cur.unresolved where !unresolved.contains(num) { unresolved.append(num) }
            return cur.value
        }
        var inner: [String] = []
        let value = try resolve(elem.variable.value, stack: stack + [name], unresolved: &inner)
        cache[name] = (value, inner)
        for num in inner where !unresolved.contains(num) { unresolved.append(num) }
        return value
    }

    private func dynamic(_ name: String) -> String? {
        switch name {
        case "$uuid": return UUID().uuidString.lowercased()
        case "$ulid": return ULID.make()
        case "$timestamp": return String(Int64(now.timeIntervalSince1970))
        case "$timestampMs": return String(Int64(now.timeIntervalSince1970 * 1000))
        case "$isoTimestamp":
            let fn = ISO8601DateFormatter()
            fn.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fn.string(from: now)
        case "$randomInt": return String(Int.random(in: 0...1000))
        case "$randomString":
            let alnum = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
            return String((0..<16).map { _ in alnum.randomElement()! })
        default: return nil
        }
    }

    /// Název proměnné `[A-Za-z0-9_.-]+`.
    static func isValidName(_ str: String) -> Bool {
        !str.isEmpty
            && str.unicodeScalars.allSatisfy {
                ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)
                    || "_.-".unicodeScalars.contains($0)
            }
    }
}
