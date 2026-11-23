import Foundation
import Security
import Synchronization

/// Úložiště hodnot tajných proměnných (PLAN 2.8). Účet = `<projectId>/<envId>/<name>` nebo `global/<name>`.
public protocol SecretStore: Sendable {
    func get(account: String) throws -> String?
    /// Prázdná hodnota položku smaže.
    func set(account: String, value: String) throws
    /// Neexistující položka není chyba.
    func delete(account: String) throws
}

/// Keychain přes `SecItem` (legacy file keychain), služba `MinorREST`; chyby jako `SECRET_ERROR`.
public struct Secrets: SecretStore {
    public static let service = "MinorREST"
    public let service: String

    public init(service: String = Self.service) {
        self.service = service
    }

    public static func account(projectID: String, envID: String, name: String) -> String {
        "\(projectID)/\(envID)/\(name)"
    }

    public static func globalAccount(_ name: String) -> String { "global/\(name)" }

    private func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    public func get(account: String) throws -> String? {
        var q = query(account)
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        var out: CFTypeRef?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        if st == errSecItemNotFound { return nil }
        try Self.check(st, account)
        guard let data = out as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public func set(account: String, value: String) throws {
        if value.isEmpty { return try delete(account: account) }
        let data = Data(value.utf8)
        let st = SecItemUpdate(query(account) as CFDictionary, [kSecValueData: data] as CFDictionary)
        if st != errSecItemNotFound { return try Self.check(st, account) }
        var add = query(account)
        add[kSecValueData] = data
        add[kSecAttrLabel] = service
        try Self.check(SecItemAdd(add as CFDictionary, nil), account)
    }

    public func delete(account: String) throws {
        let st = SecItemDelete(query(account) as CFDictionary)
        if st != errSecItemNotFound { try Self.check(st, account) }
    }

    private static func check(_ st: OSStatus, _ account: String) throws {
        guard st != errSecSuccess else { return }
        let msg = SecCopyErrorMessageString(st, nil) as String? ?? "OSStatus \(st)"
        throw CoreError(.secretError, "\(account): \(msg)")
    }
}

/// Tajemství jen v paměti (testy, read-only náhledy).
public final class MemorySecrets: SecretStore {
    private let items = Mutex<[String: String]>([:])

    public init(_ initial: [String: String] = [:]) {
        items.withLock { $0 = initial }
    }

    public var all: [String: String] { items.withLock { $0 } }

    public func get(account: String) throws -> String? { items.withLock { $0[account] } }

    public func set(account: String, value: String) throws {
        items.withLock { $0[account] = value.isEmpty ? nil : value }
    }

    public func delete(account: String) throws { _ = items.withLock { $0.removeValue(forKey: account) } }
}

extension SecretStore {
    /// Doplní hodnoty tajných proměnných; prázdný Keychain ponechá hodnotu z YAML (převede se při uložení).
    public func fill(_ vars: [Var], account: (String) -> String) throws -> [Var] {
        try vars.map { v in
            guard v.secret, !v.name.isEmpty else { return v }
            var v = v
            if let s = try get(account: account(v.name)) { v.value = s }
            return v
        }
    }

    /// Zapíše hodnoty tajných proměnných `new` a smaže položky tajných názvů z `old`, které v `new`
    /// tajné nejsou (přejmenování = přesun, smazání = smazání položky).
    public func sync(old: [Var], new: [Var], account: (String) -> String) throws {
        let keep = Set(new.filter { $0.secret && !$0.name.isEmpty }.map(\.name))
        for v in new where v.secret && !v.name.isEmpty {
            try set(account: account(v.name), value: v.value)
        }
        for name in Set(old.filter(\.secret).map(\.name)) where !name.isEmpty && !keep.contains(name) {
            try delete(account: account(name))
        }
    }

    /// Smaže položky všech tajných proměnných.
    public func deleteAll(_ vars: [Var], account: (String) -> String) throws {
        for v in vars where v.secret && !v.name.isEmpty { try delete(account: account(v.name)) }
    }
}

extension Array where Element == Var {
    /// Tajné proměnné bez hodnoty (zápis do YAML).
    var withoutSecretValues: [Var] {
        map { v in
            var v = v
            if v.secret { v.value = "" }
            return v
        }
    }
}
