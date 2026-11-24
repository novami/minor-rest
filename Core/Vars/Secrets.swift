import Foundation
import MinorKeychain
import Synchronization

/// Úložiště hodnot tajemství. Účet = `<projectId>/<envId>/<name>`, `global/<name>`, `req/<requestId>/<pole>`.
nonisolated protocol SecretStore: Sendable {
    func get(account: String) throws -> String?
    /// Prázdná hodnota položku smaže.
    func set(account: String, value: String) throws
    /// Neexistující položka není chyba.
    func delete(account: String) throws
}

/// Keychain přes `MinorKeychain`; služba `MinorREST` zůstává kvůli už uloženým položkám. Chyby jako `SECRET_ERROR`.
nonisolated struct Secrets: SecretStore {
    static let service = "MinorREST"
    private let keychain: Keychain

    init(service: String = Self.service) {
        keychain = Keychain(service: service)
    }

    static func account(projectID: String, envID: String, name: String) -> String {
        "\(projectID)/\(envID)/\(name)"
    }

    static func globalAccount(_ name: String) -> String { "global/\(name)" }

    func get(account: String) throws -> String? {
        try wrap(account) { try keychain.string(for: account) }
    }

    func set(account: String, value: String) throws {
        if value.isEmpty { return try delete(account: account) }
        try wrap(account) { try keychain.set(value, for: account) }
    }

    func delete(account: String) throws {
        try wrap(account) { try keychain.remove(account) }
    }

    private func wrap<T>(_ account: String, _ body: () throws -> T) throws -> T {
        do { return try body() } catch let elem as KeychainError {
            throw CoreError(.secretError, "\(account): \(elem.message)")
        }
    }
}

/// Tajemství jen v paměti (testy, read-only náhledy).
nonisolated final class MemorySecrets: SecretStore {
    private let items = Mutex<[String: String]>([:])

    init(_ initial: [String: String] = [:]) {
        items.withLock { $0 = initial }
    }

    var all: [String: String] { items.withLock { $0 } }

    func get(account: String) throws -> String? { items.withLock { $0[account] } }

    func set(account: String, value: String) throws {
        items.withLock { $0[account] = value.isEmpty ? nil : value }
    }

    func delete(account: String) throws { _ = items.withLock { $0.removeValue(forKey: account) } }
}

nonisolated extension SecretStore {
    /// Doplní hodnoty tajných proměnných; prázdný Keychain ponechá hodnotu z YAML (převede se při uložení).
    func fill(_ vars: [Var], account: (String) -> String) throws -> [Var] {
        try vars.map { val in
            guard val.secret, !val.name.isEmpty else { return val }
            var val = val
            if let str = try get(account: account(val.name)) { val.value = str }
            return val
        }
    }

    /// Zapíše hodnoty tajných proměnných `new` a smaže položky tajných názvů z `old`, které v `new`
    /// tajné nejsou (přejmenování = přesun, smazání = smazání položky).
    func sync(old: [Var], new: [Var], account: (String) -> String) throws {
        let keep = Set(new.filter { $0.secret && !$0.name.isEmpty }.map(\.name))
        for val in new where val.secret && !val.name.isEmpty {
            try set(account: account(val.name), value: val.value)
        }
        for name in Set(old.filter(\.secret).map(\.name)) where !name.isEmpty && !keep.contains(name) {
            try delete(account: account(name))
        }
    }

    /// Smaže položky všech tajných proměnných.
    func deleteAll(_ vars: [Var], account: (String) -> String) throws {
        for val in vars where val.secret && !val.name.isEmpty { try delete(account: account(val.name)) }
    }
}

nonisolated extension Array where Element == Var {
    /// Tajné proměnné bez hodnoty (zápis do YAML).
    var withoutSecretValues: [Var] {
        map { val in
            var val = val
            if val.secret { val.value = "" }
            return val
        }
    }
}
