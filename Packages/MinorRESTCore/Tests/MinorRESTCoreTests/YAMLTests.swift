import Foundation
import Testing
@testable import MinorRESTCore

/// Fixtures v `Fixtures/go` zapsala Go verze (tag go-wails-f4, `gopkg.in/yaml.v3`).
private func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/go/\(name)", withExtension: nil))
    return try String(contentsOf: url, encoding: .utf8)
}

private struct ScalarDoc: YAMLCodable {
    var v: String
    var yaml: YNode { .map([YEntry(key: "v", value: .string(v))]) }
    init(v: String) { self.v = v }
    init(yaml o: YAMLObject) throws { v = try o.string("v") }
}

private struct ScalarCase: Decodable, CustomTestStringConvertible {
    let input: String
    let yaml: String
    enum CodingKeys: String, CodingKey { case input = "in", yaml }
    var testDescription: String { input.debugDescription }
}

private func scalarCases() throws -> [ScalarCase] {
    try JSONDecoder().decode([ScalarCase].self, from: Data(fixture("scalars.json").utf8))
}

@Suite struct YAMLTests {
    /// Styl zápisu řetězců bajtově shodný s yaml.v3. Výjimka: yaml.v3 u literálu začínajícího
    /// novým řádkem tento řádek ztratí (chyba Go verze) – my ho zachováme.
    @Test func scalarsMatchGo() throws {
        for c in try scalarCases() where c.input != "\nx" {
            #expect(YAML.encode(ScalarDoc(v: c.input)) == c.yaml, "\(c.input.debugDescription)")
        }
    }

    @Test func scalarsRoundtrip() throws {
        for c in try scalarCases() {
            let decoded = try YAML.decode(ScalarDoc.self, from: YAML.encode(ScalarDoc(v: c.input)))
            #expect(decoded.v == c.input.nfc, "\(c.input.debugDescription)")
        }
    }

    @Test(arguments: [
        "request-full.req.yaml", "request-new.req.yaml", "request-oauth.req.yaml", "request-basic.req.yaml",
    ])
    func requestMatchesGo(file: String) throws {
        let text = try fixture(file)
        #expect(YAML.encode(try YAML.decode(Request.self, from: text)) == text)
    }

    @Test func configsMatchGo() throws {
        for file in ["project.yaml", "project-min.yaml"] {
            let text = try fixture(file)
            #expect(YAML.encode(try YAML.decode(ProjectConfig.self, from: text)) == text, "\(file)")
        }
        for file in ["folder.yaml", "folder-min.yaml"] {
            let text = try fixture(file)
            #expect(YAML.encode(try YAML.decode(FolderConfig.self, from: text)) == text, "\(file)")
        }
        let env = try fixture("environment.yaml")
        #expect(YAML.encode(try YAML.decode(Environment.self, from: env)) == env)
    }

    @Test func requestFieldsFromGo() throws {
        let r = try YAML.decode(Request.self, from: fixture("request-full.req.yaml"))
        #expect(r.name == "Seznam uživatelů")
        #expect(r.body.raw == "{\n  \"jméno\": \"Žluťoučký\",\n\t\"x\": 1\n}\n")
        #expect(r.params.query[2] == KV(name: "wsdl", bare: true))
        #expect(r.params.query[1].enabled == false)
        #expect(r.auth.bearer == BearerAuth(token: "{{token}}", prefix: "Bearer"))
        #expect(r.settings == HTTPSettings(httpVersion: "http2", followRedirects: false, maxRedirects: 0,
                                           timeoutMs: 5000, verifyTLS: true, cookieJar: false))
        #expect(r.vars[1] == Var(name: "off", enabled: false))
    }

    @Test func defaultsNFCAndErrors() throws {
        let nfd = "Kůň".decomposedStringWithCanonicalMapping
        let src = "id: x\nname: \(nfd)\nmethod: GET\nurl: u\nheaders:\n  - { name: A, value: b }\n  - { name: C, value: d, enabled: false }\n"
        let r = try YAML.decode(Request.self, from: src)
        #expect(r.name == "Kůň" && r.name.unicodeScalars.count == 3)
        #expect(r.headers[0].enabled && !r.headers[1].enabled)

        for bad in ["name: [x", "seq: abc", "headers: x", "- a"] {
            #expect(throws: CoreError.self, "\(bad)") { try YAML.decode(Request.self, from: bad) }
            do { _ = try YAML.decode(Request.self, from: bad) } catch let e as CoreError {
                #expect(e.code == .yamlInvalid)
            }
        }
        #expect(try YAML.decode(Request.self, from: "") == Request())
    }

    @Test func newRequestIsMinimal() {
        #expect(YAML.encode(Request.new(id: "X", name: "Nový")) ==
            "id: X\nname: Nový\nseq: 0\nmethod: GET\nurl: \"\"\nauth:\n  type: inherit\nbody:\n  type: none\n")
    }
}
