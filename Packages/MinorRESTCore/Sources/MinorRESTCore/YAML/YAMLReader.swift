import Foundation
import Yams

public protocol YAMLEncodable {
    var yaml: YNode { get }
}

public protocol YAMLDecodable {
    init(yaml: YAMLObject) throws
}

public typealias YAMLCodable = YAMLEncodable & YAMLDecodable

public enum YAML {
    /// Zápis dokumentu (formát shodný s Go verzí).
    public static func encode<T: YAMLEncodable>(_ value: T) -> String {
        YAMLWriter.document(value.yaml)
    }

    /// Čtení dokumentu; chyba syntaxe nebo typu → `YAML_INVALID`. Řetězce se normalizují do NFC.
    public static func decode<T: YAMLDecodable>(_ type: T.Type = T.self, from text: String) throws -> T {
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
public struct YAMLObject {
    let node: Node?
    let path: String

    init(node: Node?, path: String) {
        self.node = node
        self.path = path
    }

    private func value(_ key: String) throws -> Node? {
        guard let node, !isNull(node) else { return nil }
        guard case .mapping = node else { throw invalid(path.isEmpty ? "document" : path, "expected mapping") }
        guard let v = node[key], !isNull(v) else { return nil }
        return v
    }

    private func isNull(_ node: Node) -> Bool {
        guard let s = node.scalar, s.style == .plain else { return false }
        return ["", "~", "null", "Null", "NULL"].contains(s.string)
    }

    private func invalid(_ key: String, _ message: String) -> CoreError {
        CoreError(.yamlInvalid, "\(key): \(message)")
    }

    private func keyPath(_ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }

    public func string(_ key: String) throws -> String {
        try optionalString(key) ?? ""
    }

    public func optionalString(_ key: String) throws -> String? {
        guard let v = try value(key) else { return nil }
        guard let s = v.scalar else { throw invalid(keyPath(key), "expected string") }
        return s.string.nfc
    }

    public func int(_ key: String) throws -> Int { try optionalInt(key) ?? 0 }

    public func optionalInt(_ key: String) throws -> Int? {
        guard let v = try value(key) else { return nil }
        guard let i = v.int else { throw invalid(keyPath(key), "expected integer") }
        return i
    }

    public func bool(_ key: String, default fallback: Bool = false) throws -> Bool {
        try optionalBool(key) ?? fallback
    }

    public func optionalBool(_ key: String) throws -> Bool? {
        guard let v = try value(key) else { return nil }
        guard let s = v.scalar else { throw invalid(keyPath(key), "expected boolean") }
        switch s.string {
        case "true", "True", "TRUE": return true
        case "false", "False", "FALSE": return false
        default: throw invalid(keyPath(key), "expected boolean")
        }
    }

    public func object<T: YAMLDecodable>(_ key: String) throws -> T? {
        guard let v = try value(key) else { return nil }
        guard case .mapping = v else { throw invalid(keyPath(key), "expected mapping") }
        return try T(yaml: YAMLObject(node: v, path: keyPath(key)))
    }

    public func list<T: YAMLDecodable>(_ key: String) throws -> [T] {
        guard let v = try value(key) else { return [] }
        guard case .sequence(let seq) = v else { throw invalid(keyPath(key), "expected list") }
        return try seq.enumerated().map { i, item in
            let p = "\(keyPath(key))[\(i)]"
            guard case .mapping = item else { throw invalid(p, "expected mapping") }
            return try T(yaml: YAMLObject(node: item, path: p))
        }
    }
}
