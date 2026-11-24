import Foundation
import Yams

/// Neutrální podoba specifikace (Swagger 2.0 i OpenAPI 3.x) – vstup generátoru (kap. 7).
nonisolated struct APISpec: Sendable, Equatable {
    var title = ""
    var description = ""
    var servers: [APIServer] = []
    /// Globální autentizace (první požadavek `security`); `nil` = žádná.
    var auth: Auth?
    /// Názvy proměnných použitých v autentizaci (`username`, `token` …), které se založí prázdné.
    var variables: [String] = []
    var operations: [APIOperation] = []
    var warnings: [String] = []
}

nonisolated struct APIServer: Sendable, Equatable {
    var url: String
    var description: String
}

nonisolated struct APIOperation: Sendable, Equatable {
    var method = ""
    /// Cesta s parametry ve tvaru `:id`.
    var path = ""
    var tag = ""
    var summary = ""
    var operationId = ""
    var description = ""
    var query: [KeyValue] = []
    var headers: [KeyValue] = []
    var pathParams: [PathParam] = []
    var body: Body?
    /// `nil` = zdědit; `none` při `security: []`; jinak vlastní schéma operace.
    var auth: Auth?

    /// Název requestu: `summary` → `operationId` → `METHOD /path`.
    var title: String {
        if !summary.isEmpty { return summary }
        if !operationId.isEmpty { return operationId }
        let shown = path.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.hasPrefix(":") ? "{\($0.dropFirst())}" : String($0) }.joined(separator: "/")
        return "\(method) \(shown)"
    }
}

// MARK: - Parser

nonisolated enum OpenAPIParser {
    static func parse(_ text: String) throws -> APISpec {
        let root: Node
        do {
            guard let numVal = try Yams.compose(yaml: text) else { throw CoreError(.importInvalid, "empty") }
            root = numVal
        } catch let elem as CoreError {
            throw elem
        } catch {
            throw CoreError(.importInvalid, "\(error)")
        }
        guard root.mapping != nil else { throw CoreError(.importInvalid, "not an object") }
        var par = SpecParser(root: SpecNode(root))
        guard par.v2 || par.v3 else { throw CoreError(.importInvalid, "swagger/openapi") }
        return par.run()
    }
}

/// Tenký obal nad `Node` (bez výjimek; chybějící klíč = prázdný uzel).
