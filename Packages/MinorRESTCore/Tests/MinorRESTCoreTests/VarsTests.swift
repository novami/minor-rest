import Foundation
import Testing
@testable import MinorRESTCore

private func v(_ name: String, _ value: String, secret: Bool = false, enabled: Bool = true) -> Var {
    Var(name: name, value: value, secret: secret, enabled: enabled)
}

private func errorCode(_ body: () throws -> Void) -> ErrorCode? {
    do { try body() } catch let e as CoreError { return e.code } catch { return nil }
    return nil
}

@Suite struct VarsTests {
    let resolver = Resolver(scopes: [
        VarScope(.runtime, vars: [v("token", "runtime")]),
        VarScope(.request, vars: [v("x", "vypnutá", enabled: false), v("page", "2")]),
        VarScope(.folder, ref: "a/b", vars: [v("x", "složka-b")]),
        VarScope(.folder, ref: "a", vars: [v("x", "složka-a"), v("host", "a.cz")]),
        VarScope(.environment, vars: [v("token", "env"), v("host", "env.cz")]),
        VarScope(.project, vars: [v("base", "https://{{host}}/api")]),
        VarScope(.global, vars: [v("base", "global")]),
    ])

    @Test(arguments: [
        ("{{token}}", "runtime", [String]()),
        ("{{ x }}", "složka-b", []),
        ("{{base}}/u?p={{page}}", "https://a.cz/api/u?p=2", []),
        ("{{nic}}/{{$neznama}}/{{nic}}", "{{nic}}/{{$neznama}}/{{nic}}", ["nic", "$neznama"]),
        (#"\{{token}} {{token}}"#, "{{token}} runtime", []),
        ("{{ne platné}} {{", "{{ne platné}} {{", []),
        ("Kůň {{x}}", "Kůň složka-b", []),
    ])
    func priorityAndUnknown(input: String, expected: String, unresolved: [String]) throws {
        let (got, unres) = try resolver.resolve(input)
        #expect(got == expected)
        #expect(unres == unresolved)
    }

    @Test func unresolvedAndExplain() throws {
        _ = try resolver.resolve("{{nic}}/{{$neznama}}")
        #expect(resolver.unresolved == ["$neznama", "nic"])
        let info = resolver.explain()
        #expect(info.count == 5)
        #expect(info[0].name == "base" && info[0].resolved == "https://a.cz/api" && info[0].source == .project)

        let masked = Resolver(scopes: [VarScope(.environment, vars: [v("key", "tajne123", secret: true), v("auth", "Bearer {{key}}")])]).explain()
        #expect(masked[0].resolved == "Bearer ***")
        #expect(masked[1].value.isEmpty && masked[1].resolved.isEmpty && masked[1].secret)
    }

    @Test func cycleAndDepth() throws {
        let cycle = Resolver(scopes: [VarScope(.request, vars: [v("a", "{{b}}"), v("b", "x{{a}}")])])
        #expect(errorCode { _ = try cycle.resolve("{{a}}") } == .varCycle)

        let letters = (0..<13).map { String(UnicodeScalar(UInt8(97 + $0))) }
        let chain = Resolver(scopes: [VarScope(.request, vars: (0..<12).map { v(letters[$0], "{{\(letters[$0 + 1])}}") })])
        #expect(errorCode { _ = try chain.resolve("{{a}}") } == .varCycle)

        let repeated = Resolver(scopes: [VarScope(.request, vars: [v("a", "{{b}}{{b}}"), v("b", "1")])])
        #expect(try repeated.resolve("{{a}}").value == "11")
    }

    @Test func dynamic() throws {
        let r = Resolver()
        let f = try r.resolve("{{$uuid}} {{$uuid}} {{$timestamp}} {{$timestamp}} {{$randomString}} {{$isoTimestamp}} {{$randomInt}}")
            .value.split(separator: " ").map(String.init)
        #expect(f[0].count == 36 && f[0] != f[1] && f[0] == f[0].lowercased())
        #expect(f[2] == f[3])
        #expect(f[4].count == 16)
        #expect(f[5].wholeMatch(of: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/) != nil)
        #expect((0...1000).contains(Int(f[6]) ?? -1))

        let named = Resolver(scopes: [VarScope(.request, vars: [v("id", "{{$uuid}}"), v("x", "{{nic}}")])])
        let (got, unres) = try named.resolve("{{id}} {{id}} {{x}}")
        let parts = got.split(separator: " ")
        #expect(parts[0] == parts[1])
        #expect(unres == ["nic"])
        #expect(try named.resolve("{{x}}").unresolved == ["nic"]) // i z cache
    }

    @Test(arguments: [
        ("kůň", "k%C5%AF%C5%88"),
        ("a b+c&d=e#f", "a%20b%2Bc%26d%3De%23f"),
        ("už%20kódováno", "u%C5%BE%20k%C3%B3dov%C3%A1no"),
        ("100%", "100%25"),
        ("%zz", "%25zz"),
        ("a/b:c@d,e;f?g", "a/b:c@d,e;f?g"),
    ])
    func encodeQueryComponent(input: String, expected: String) {
        #expect(URLBuilder.encodeQueryComponent(input) == expected)
    }

    @Test func buildURL() throws {
        let r = Resolver(scopes: [VarScope(.environment, vars: [
            v("baseUrl", "localhost:8080"), v("id", "a b/č"), v("q", "Žluťoučký kůň"),
        ])])
        let path = [PathParam(name: "id", value: "{{id}}"), PathParam(name: "fmt", value: "json")]
        let query = [
            KV(name: "q", value: "{{q}}"),
            KV(name: "vypnuty", value: "1", enabled: false),
            KV(name: "flag"),
            KV(name: "wsdl", bare: true),
            KV(name: "pct", value: "%2F"),
        ]
        #expect(try URLBuilder.build("{{baseUrl}}/users/:id/x.:fmt/:neni", path: path, query: query, resolver: r) ==
            "http://localhost:8080/users/a%20b%2F%C4%8D/x.:fmt/:neni?q=%C5%BDlu%C5%A5ou%C4%8Dk%C3%BD%20k%C5%AF%C5%88&flag=&wsdl&pct=%2F")

        do {
            _ = try URLBuilder.build("{{nic}}/a", path: [], query: [], resolver: r)
            Issue.record("expected error")
        } catch let e as CoreError {
            #expect(e == CoreError(.varUnresolvedHost, "nic"))
        }
        for bad in ["http://a b/", "http://[::1", "http://:80/", "http://", "ht tp://x", "http://x:8a/"] {
            #expect(errorCode { _ = try URLBuilder.build(bad, path: [], query: [], resolver: r) } == .urlInvalid, "\(bad)")
        }
        #expect(try URLBuilder.build("https://api.cz/u/:id", path: [path[0]], query: [], resolver: Resolver()) ==
            "https://api.cz/u/%7B%7Bid%7D%7D")
        #expect(try URLBuilder.build("  api.cz/a?x=1  ", path: [], query: [KV(name: "y", value: "2")], resolver: r) ==
            "http://api.cz/a?x=1&y=2")
        #expect(try URLBuilder.build("http://[::1]:8080/a", path: [], query: [], resolver: r) == "http://[::1]:8080/a")
    }
}

@Suite struct JSONFormatterTests {
    @Test(arguments: [
        (#"{"a":1,"b":[true,null]}"#, "{\n  \"a\": 1,\n  \"b\": [\n    true,\n    null\n  ]\n}"),
        (#"{"big":12345678901234567890.10}"#, "{\n  \"big\": 12345678901234567890.10\n}"),
        (#"{"id":{{id}},"s":"{{name}}","t":"x {{a}} y","e":"\{{no}}"}"#,
         "{\n  \"id\": {{id}},\n  \"s\": \"{{name}}\",\n  \"t\": \"x {{a}} y\",\n  \"e\": \"\\{{no}}\"\n}"),
        (#"{"q":"a\"{{v}}"}"#, "{\n  \"q\": \"a\\\"{{v}}\"\n}"),
        (" [ {}, [], {\"k\":\"ž\\u00e1\"} ]\n", "[\n  {},\n  [],\n  {\n    \"k\": \"ž\\u00e1\"\n  }\n]\n"),
        ("{ {{key}} : -0.5e+3 }", "{\n  {{key}}: -0.5e+3\n}"),
    ])
    func format(input: String, expected: String) throws {
        #expect(try JSONFormatter.format(input) == expected)
        #expect(JSONFormatter.validate(input) == nil)
    }

    @Test(arguments: [
        ("{\n\"a\": }", "2:"),
        ("", "1:"),
        ("[1,]", "1:"),
        ("{\"a\" 1}", "1:"),
        ("01", "1:"),
        ("\"a\\x\"", "1:"),
        ("[1] [2]", "1:"),
        ("{\"a\":tru}", "1:"),
        ("\n\n[1.]", "3:"),
    ])
    func invalid(input: String, linePrefix: String) {
        do {
            _ = try JSONFormatter.format(input)
            Issue.record("expected error for \(input.debugDescription)")
        } catch let e as CoreError {
            #expect(e.code == .jsonInvalid && e.detail.hasPrefix(linePrefix), "\(e)")
        } catch {
            Issue.record("\(error)")
        }
        #expect(JSONFormatter.validate(input)?.code == .jsonInvalid)
    }

    @Test func largeDocumentIsFast() throws {
        let item = #"{"id":123,"name":"Žluťoučký kůň","tags":["a","b"],"nested":{"x":1.5,"y":null}}"#
        let big = "[" + Array(repeating: item, count: 50_000).joined(separator: ",") + "]" // ~4 MB
        let clock = ContinuousClock()
        let elapsed = try clock.measure { _ = try JSONFormatter.format(big) }
        #expect(elapsed < .seconds(3), "\(elapsed)")
    }
}
