import Foundation
import Yams

nonisolated protocol YAMLEncodable {
    var yaml: YNode { get }
}

nonisolated protocol YAMLDecodable {
    init(yaml: YAMLObject) throws
}

typealias YAMLCodable = YAMLEncodable & YAMLDecodable

nonisolated enum YAML {
    /// Zápis dokumentu (formát shodný s Go verzí).
    static func encode<T: YAMLEncodable>(_ value: T) -> String {
        YAMLWriter.document(value.yaml)
    }

    /// Čtení dokumentu; chyba syntaxe nebo typu → `YAML_INVALID`. Řetězce se normalizují do NFC.
    static func decode<T: YAMLDecodable>(_ type: T.Type = T.self, from text: String) throws -> T {
        let node: Node?
        do {
            node = try Yams.compose(yaml: text)
        } catch {
            throw CoreError(.yamlInvalid, "\(error)")
        }
        return try T(yaml: YAMLObject(node: node, path: ""))
    }
}

/// Přístup k mapě YAML s výchozími hodnotami pro chybějící klíče.
nonisolated struct YAMLObject {
    let node: Node?
    let path: String

    private func value(_ key: String) throws -> Node? {
        guard let node, !isNull(node) else { return nil }
        guard case .mapping = node else { throw invalid(path.isEmpty ? "document" : path, "expected mapping") }
        guard let val = node[key], !isNull(val) else { return nil }
        return val
    }

    private func isNull(_ node: Node) -> Bool {
        guard let str = node.scalar, str.style == .plain else { return false }
        return ["", "~", "null", "Null", "NULL"].contains(str.string)
    }

    private func invalid(_ key: String, _ message: String) -> CoreError {
        CoreError(.yamlInvalid, "\(key): \(message)")
    }

    private func keyPath(_ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }

    func string(_ key: String) throws -> String {
        try optionalString(key) ?? ""
    }

    func optionalString(_ key: String) throws -> String? {
        guard let val = try value(key) else { return nil }
        guard let str = val.scalar else { throw invalid(keyPath(key), "expected string") }
        return str.string.nfc
    }

    func int(_ key: String) throws -> Int { try optionalInt(key) ?? 0 }

    func optionalInt(_ key: String) throws -> Int? {
        guard let val = try value(key) else { return nil }
        guard let i = val.int else { throw invalid(keyPath(key), "expected integer") }
        return i
    }

    func double(_ key: String) throws -> Double {
        guard let val = try value(key) else { return 0 }
        guard let dat = val.float else { throw invalid(keyPath(key), "expected number") }
        return dat
    }

    func bool(_ key: String, default fallback: Bool = false) throws -> Bool {
        try optionalBool(key) ?? fallback
    }

    func optionalBool(_ key: String) throws -> Bool? {
        guard let val = try value(key) else { return nil }
        guard let str = val.scalar else { throw invalid(keyPath(key), "expected boolean") }
        switch str.string {
        case "true", "True", "TRUE": return true
        case "false", "False", "FALSE": return false
        default: throw invalid(keyPath(key), "expected boolean")
        }
    }

    func stringList(_ key: String) throws -> [String] {
        guard let val = try value(key) else { return [] }
        guard case .sequence(let seq) = val else { throw invalid(keyPath(key), "expected list") }
        return try seq.map { item in
            guard let str = item.scalar else { throw invalid(keyPath(key), "expected string") }
            return str.string.nfc
        }
    }

    /// Mapa s libovolnými klíči a hodnotami-řetězci.
    func stringMap(_ key: String) throws -> [String: String] {
        try entries(key).reduce(into: [:]) { out, elem in
            guard let str = elem.value.scalar else { throw invalid("\(keyPath(key)).\(elem.key)", "expected string") }
            out[elem.key] = str.string.nfc
        }
    }

    /// Mapa s libovolnými klíči a hodnotami-seznamy řetězců.
    func stringListMap(_ key: String) throws -> [String: [String]] {
        guard let val = try value(key) else { return [:] }
        let inner = YAMLObject(node: val, path: keyPath(key))
        return try entries(key).reduce(into: [:]) { out, elem in out[elem.key] = try inner.stringList(elem.key) }
    }

    private func entries(_ key: String) throws -> [(key: String, value: Node)] {
        guard let val = try value(key) else { return [] }
        guard case .mapping(let map) = val else { throw invalid(keyPath(key), "expected mapping") }
        return map.compactMap { keyVal, val in keyVal.scalar.map { ($0.string.nfc, val) } }
    }

    func object<T: YAMLDecodable>(_ key: String) throws -> T? {
        guard let val = try value(key) else { return nil }
        guard case .mapping = val else { throw invalid(keyPath(key), "expected mapping") }
        return try T(yaml: YAMLObject(node: val, path: keyPath(key)))
    }

    func list<T: YAMLDecodable>(_ key: String) throws -> [T] {
        guard let val = try value(key) else { return [] }
        guard case .sequence(let seq) = val else { throw invalid(keyPath(key), "expected list") }
        return try seq.enumerated().map { i, item in
            let par = "\(keyPath(key))[\(i)]"
            guard case .mapping = item else { throw invalid(par, "expected mapping") }
            return try T(yaml: YAMLObject(node: item, path: par))
        }
    }
}
